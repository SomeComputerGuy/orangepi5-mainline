#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# add-debug.py <rkvdec dir>: adds the DEBUG-only (never landed) instrumentation of
# the rkvdec-reset test builds: register dumps of the core and its IOMMU at each step
# of rkvdec_core_recover(), and fault injection (inject_fault=N: every Nth VDPU381
# job gets an unmapped IOVA in one of its address registers).
import sys, os
d = sys.argv[1]
def rep(p, old, new, cnt=1):
    p = os.path.join(d, p); s = open(p).read()
    assert old in s, (p, old[:80]); s = s.replace(old, new, cnt); open(p, 'w').write(s)

rep('rkvdec.h', '''	int irq;
	bool broken;''', '''	int irq;
	bool broken;
	void __iomem *dbg_mmu[2];
	unsigned int dbg_jobs;''')
rep('rkvdec.h', 'void rkvdec_quirks_disable_qos(struct rkvdec_ctx *ctx);',
    'void rkvdec_quirks_disable_qos(struct rkvdec_ctx *ctx);\nvoid rkvdec_dbg_inject(struct rkvdec_core *core);')

DBG = r'''
/* DEBUG (rkvdec-reset test builds only) */
static bool dbg_reset = true;
module_param(dbg_reset, bool, 0644);
static uint inject_fault;
module_param(inject_fault, uint, 0644);
static uint inject_reg = 2;	/* register index in the common address block: 0 rlc (read), 2 decout (write) */
module_param(inject_reg, uint, 0644);
static uint inject_iova;
module_param(inject_iova, uint, 0644);
static atomic_t dbg_recovers = ATOMIC_INIT(0);

static void rkvdec_dbg_dump(struct rkvdec_core *core, const char *step)
{
	u32 m[2][3] = {}, sta = 0, dbg = 0;
	int b;

	if (!dbg_reset)
		return;
	for (b = 0; b < 2; b++) {
		if (!core->dbg_mmu[b])
			continue;
		m[b][0] = readl(core->dbg_mmu[b] + 0x00);	/* DTE_ADDR */
		m[b][1] = readl(core->dbg_mmu[b] + 0x04);	/* STATUS */
		m[b][2] = readl(core->dbg_mmu[b] + 0x14);	/* INT_RAWSTAT */
	}
	if (core->variant->ops->irq_handler == vdpu381_irq_handler) {
		sta = readl(core->regs + VDPU381_REG_STA_INT);
		dbg = readl(core->regs + VDPU381_REG_DEBUG_INT);
	}
	dev_info(core->dev, "rkvdec-dbg %-9s mmu0 dte %08x st %08x raw %x mmu1 dte %08x st %08x raw %x sta %08x dbg %08x\n",
		 step, m[0][0], m[0][1], m[0][2], m[1][0], m[1][1], m[1][2], sta, dbg);
}

/*
 * inject_iova=0: use the physical address of a 4 MiB canary buffer as the unmapped IOVA,
 * so that an access that bypasses the IOMMU lands in the canary and is seen.
 */
static void *dbg_canary;
static phys_addr_t dbg_canary_pa;
#define DBG_CANARY_ORDER 10
#define DBG_CANARY_SIZE (PAGE_SIZE << DBG_CANARY_ORDER)

static void rkvdec_dbg_check_canary(struct rkvdec_core *core, const char *when)
{
	if (dbg_canary && memchr_inv(dbg_canary, 0xa5, DBG_CANARY_SIZE)) {
		dev_err(core->dev, "rkvdec-dbg CANARY HIT (%s): memory at %pa written\n", when, &dbg_canary_pa);
		memset(dbg_canary, 0xa5, DBG_CANARY_SIZE);
	}
}

/*
 * Reserved-RAM canary: a no-map reserved-memory region of the test DTB (dbg_rcanary_pa/size)
 * filled with a pattern; a write that escapes the IOMMU to an IOVA in that range lands in it.
 * dbg_min_iova: the lowest buffer IOVA programmed so far, to show the IOVAs reach the range.
 */
static ulong dbg_rcanary_pa;
module_param(dbg_rcanary_pa, ulong, 0444);
static ulong dbg_rcanary_size;
module_param(dbg_rcanary_size, ulong, 0444);
static uint dbg_min_iova = 0xffffffff;
module_param(dbg_min_iova, uint, 0444);
static uint dbg_canary_hits;
module_param(dbg_canary_hits, uint, 0444);
static void *dbg_rcanary;

static void rkvdec_dbg_check_rcanary(struct rkvdec_core *core, const char *when)
{
	u8 *bad;

	if (!dbg_rcanary_size)
		return;
	if (!dbg_rcanary) {
		dbg_rcanary = memremap(dbg_rcanary_pa, dbg_rcanary_size, MEMREMAP_WB);
		if (!dbg_rcanary) {
			dev_err(core->dev, "rkvdec-dbg cannot map the RAM canary\n");
			dbg_rcanary_size = 0;
			return;
		}
		memset(dbg_rcanary, 0x5a, dbg_rcanary_size);
		dev_info(core->dev, "rkvdec-dbg RAM canary %#lx+%#lx armed\n", dbg_rcanary_pa, dbg_rcanary_size);
		return;
	}
	bad = memchr_inv(dbg_rcanary, 0x5a, dbg_rcanary_size);
	if (bad) {
		dbg_canary_hits++;
		dev_err(core->dev, "rkvdec-dbg RAM CANARY HIT (%s) at PA %#lx\n", when,
			dbg_rcanary_pa + (ulong)(bad - (u8 *)dbg_rcanary));
		memset(dbg_rcanary, 0x5a, dbg_rcanary_size);
	}
}

static void rkvdec_dbg_track_iova(struct rkvdec_core *core)
{
	int i;

	for (i = 0; i < 5; i++) {	/* rlc, rlcwrite, decout, colmv_cur, error_ref */
		u32 a = readl(core->regs + OFFSET_COMMON_ADDR_REGS + 4 * i);

		if (a && a < dbg_min_iova)
			dbg_min_iova = a;
	}
}

void rkvdec_dbg_inject(struct rkvdec_core *core)
{
	u32 iova = inject_iova;

	rkvdec_dbg_track_iova(core);
	if (dbg_rcanary_size && !dbg_rcanary)
		rkvdec_dbg_check_rcanary(core, "arm");

	if (!inject_fault || ++core->dbg_jobs % inject_fault)
		return;
	if (!iova) {
		if (!dbg_canary) {
			struct page *pg = alloc_pages(GFP_KERNEL | __GFP_DMA32, DBG_CANARY_ORDER);

			if (!pg)
				return;
			dbg_canary = page_address(pg);
			dbg_canary_pa = page_to_phys(pg);
			memset(dbg_canary, 0xa5, DBG_CANARY_SIZE);
		}
		if (iommu_iova_to_phys(core->rkvdec->iommu_global_domain, dbg_canary_pa))
			return;	/* that IOVA is mapped: no fault */
		iova = dbg_canary_pa;
	}
	dev_info(core->dev, "rkvdec-dbg inject: address register %u = %#x\n", inject_reg, iova);
	writel(iova, core->regs + OFFSET_COMMON_ADDR_REGS + 4 * inject_reg);
}
'''
rep('rkvdec.c', '\n/*\n * Reprograms the IOMMU of @core with the domain the cores share.', DBG + '\n/*\n * Reprograms the IOMMU of @core with the domain the cores share.')
# forward declaration for vdpu381_irq_handler used in dump
rep('rkvdec.c', '\n/* DEBUG (rkvdec-reset test builds only) */', '\nstatic irqreturn_t vdpu381_irq_handler(struct rkvdec_core *core);\n/* DEBUG (rkvdec-reset test builds only) */')
rep('rkvdec.c', '''	idle = core->variant->ops->reset(core);
	if (core->resets) {
		if (!idle)
			dev_warn(core->dev, "soft reset failed, pulsing the reset lines\\n");
		ret = reset_control_assert(core->resets);
		if (!ret) {
			udelay(5);
			ret = reset_control_deassert(core->resets);
		}
		idle = !ret;
	}
''', '''	if (dbg_reset)
		dev_info(core->dev, "rkvdec-dbg recover #%d\\n", atomic_inc_return(&dbg_recovers));
	rkvdec_dbg_dump(core, "enter");
	idle = core->variant->ops->reset(core);
	rkvdec_dbg_dump(core, idle ? "soft-ok" : "soft-FAIL");
	if (core->resets) {
		if (!idle)
			dev_warn(core->dev, "soft reset failed, pulsing the reset lines\\n");
		ret = reset_control_assert(core->resets);
		if (!ret) {
			udelay(5);
			ret = reset_control_deassert(core->resets);
		}
		idle = !ret;
		rkvdec_dbg_dump(core, "cru");
	}
''')
rep('rkvdec.c', '''	else if (!rkvdec_iommu_restore(core))
		idle = false;
''', '''	else if (!rkvdec_iommu_restore(core))
		idle = false;
	rkvdec_dbg_dump(core, "restored");
	rkvdec_dbg_check_canary(core, "after recovery");
	rkvdec_dbg_check_rcanary(core, "after recovery");
''')
rep('rkvdec.c', '''	status = readl(core->regs + VDPU381_REG_STA_INT);
	writel(0, core->regs + VDPU381_REG_STA_INT);
''', '''	status = readl(core->regs + VDPU381_REG_STA_INT);
	writel(0, core->regs + VDPU381_REG_STA_INT);
	if (dbg_reset && !(status & VDPU381_STA_INT_DEC_RDY_STA))
		dev_info(core->dev, "rkvdec-dbg irq sta %08x job %d\\n", status, !!READ_ONCE(core->curr_ctx));
''')
rep('rkvdec.c', '''	if (iommu_get_domain_for_dev(&pdev->dev)) {
		core->empty_domain = iommu_paging_domain_alloc(core->dev);
''', '''	{
		struct device_node *mmu_np = of_parse_phandle(pdev->dev.of_node, "iommus", 0);

		if (mmu_np) {
			core->dbg_mmu[0] = of_iomap(mmu_np, 0);
			core->dbg_mmu[1] = of_iomap(mmu_np, 1);
			of_node_put(mmu_np);
		}
	}

	if (iommu_get_domain_for_dev(&pdev->dev)) {
		core->empty_domain = iommu_paging_domain_alloc(core->dev);
''')
rep('rkvdec.c', '#include <linux/of_platform.h>\n', '#include <linux/of_address.h>\n#include <linux/of_platform.h>\n')
for f, core_expr in (('rkvdec-vdpu381-h264.c', 'core'), ('rkvdec-vdpu381-hevc.c', 'ctx->core'), ('rkvdec-vdpu381-vp9.c', None)):
    p = os.path.join(d, f); s = open(p).read()
    import re
    n = 0
    def sub(m):
        global n; n += 1
        return m.group(1) + 'rkvdec_dbg_inject(' + m.group(3) + ');\n' + m.group(1) + m.group(2)
    s2 = re.sub(r'(\t+)(writel\(VDPU381_DEC_E_BIT, (\S+?)->regs \+ VDPU381_REG_DEC_E\);)', sub, s)
    assert n == 1, (f, n)
    open(p, 'w').write(s2)
rep('rkvdec.c', '''	unsigned long axi_rate = clk_get_rate(core->axi_clk);
''', '''	unsigned long axi_rate = clk_get_rate(core->axi_clk);

	if (dbg_wd_us) {
		schedule_delayed_work(&core->watchdog_work, usecs_to_jiffies(dbg_wd_us));
		return;
	}
''')
rep('rkvdec.c', 'void rkvdec_schedule_watchdog(struct rkvdec_core *core, u32 timeout_threshold)\n',
    '/* DEBUG: watchdog override, times out jobs while their interrupt is due */\nstatic uint dbg_wd_us;\nmodule_param(dbg_wd_us, uint, 0644);\n\nvoid rkvdec_schedule_watchdog(struct rkvdec_core *core, u32 timeout_threshold)\n')
print("debug instrumentation added")
