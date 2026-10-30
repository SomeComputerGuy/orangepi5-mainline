// SPDX-License-Identifier: GPL-2.0-only
/*
 * Measurement tool, not for merging: what a CRU (reset line) reset and a soft
 * reset of an RK3588 video decoder core do to the registers of its IOMMU.
 *
 * insmod rkvdec_rstprobe.ko core=<0|1> lines=<mask> soft=<0|1>
 * (reading the core or its IOMMU while A_BIU/H_BIU are asserted raises an SError)
 * powers the core up through runtime PM (which also resumes its IOMMU), dumps
 * the IOMMU and core status registers, optionally soft resets the core, pulses
 * the selected reset lines through the CRU soft-reset registers, dumps again,
 * restores the IOMMU programming it found (DTE, interrupt mask, paging) if the
 * reset cleared it, and fails init on purpose so that it never stays loaded.
 * Run it with the decoder idle.
 *
 * lines bits (RK3588 CRU SOFTRST_CON40/41): 0 A, 1 H, 2 CA, 3 HEVC_CA,
 * 4 CORE, 5 A_BIU, 6 H_BIU.
 */
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>

static int core;
module_param(core, int, 0444);
static uint lines = 0x1f;
module_param(lines, uint, 0444);
static int soft;
module_param(soft, int, 0444);

#define CRU_BASE	0xfd7c0000
#define CRU_SOFTRST_CON(x)	(0xa00 + (x) * 4)

/* reset bit positions in SOFTRST_CON40 (core 0) / CON41 (core 1) */
static const u8 bits0[] = { 4, 3, 7, 8, 9, 6, 5 };	/* A H CA HEVC_CA CORE A_BIU H_BIU */
static const u8 bits1[] = { 3, 2, 6, 7, 8, 5, 4 };

static void __iomem *mmu, *fn, *cru;

static void dump(const char *when)
{
	int b;

	for (b = 0; b < 2; b++) {
		void __iomem *m = mmu + b * 0x40;

		pr_info("rstprobe: core%d %-14s mmu%d DTE %08x STATUS %08x INT_MASK %08x RAWSTAT %08x AUTO_GATING %08x\n",
			core, when, b, readl(m + 0x00), readl(m + 0x04), readl(m + 0x1c),
			readl(m + 0x14), readl(m + 0x24));
	}
	pr_info("rstprobe: core%d %-14s IMPORTANT_EN %08x STA_INT %08x DEBUG_INT %08x\n",
		core, when, readl(fn + 0x02c), readl(fn + 0x380), readl(fn + 0x440));
}

static int __init rstprobe_init(void)
{
	const char *name = core ? "fdc40000.video-codec" : "fdc38000.video-codec";
	phys_addr_t base = core ? 0xfdc40000 : 0xfdc38000;
	const u8 *bits = core ? bits1 : bits0;
	u32 con = core ? 41 : 40, mask = 0, dte[2], imask[2], gate[2], v;
	struct device *dev;
	int i, ret;

	dev = bus_find_device_by_name(&platform_bus_type, NULL, name);
	if (!dev)
		return -ENODEV;
	ret = pm_runtime_resume_and_get(dev);
	if (ret < 0)
		goto out_dev;

	mmu = ioremap(base + 0x700, 0x80);
	fn = ioremap(base + 0x100, 0x500);
	cru = ioremap(CRU_BASE + CRU_SOFTRST_CON(con), 4);
	if (!mmu || !fn || !cru) {
		ret = -ENOMEM;
		goto out_unmap;
	}

	for (i = 0; i < 7; i++)
		if (lines & BIT(i))
			mask |= BIT(bits[i]);

	dump("before");
	for (i = 0; i < 2; i++) {
		dte[i] = readl(mmu + i * 0x40 + 0x00);
		imask[i] = readl(mmu + i * 0x40 + 0x1c);
		gate[i] = readl(mmu + i * 0x40 + 0x24);
	}

	if (soft) {
		writel(BIT(20), fn + 0x02c);	/* SOFT_RESET_EN */
		ret = readl_poll_timeout(fn + 0x380, v, v & BIT(9), 1, 100);
		pr_info("rstprobe: core%d soft reset %s\n", core, ret ? "timed out" : "ready");
		writel(0, fn + 0x380);
		dump("after soft");
	}

	if (mask) {
		pr_info("rstprobe: core%d CRU SOFTRST_CON%u assert %#x\n", core, con, mask);
		/* No access to the core or its IOMMU while in reset: that is an SError. */
		writel(mask << 16 | mask, cru);
		udelay(5);
		writel(mask << 16, cru);
		udelay(5);
		dump("after CRU");
	}

	/* Put back what rk_iommu programmed, as rk_iommu_enable() does. */
	for (i = 0; i < 2; i++) {
		void __iomem *m = mmu + i * 0x40;

		if (readl(m + 0x00) == dte[i] && (readl(m + 0x04) & BIT(0)))
			continue;
		writel(dte[i], m + 0x00);
		writel(4, m + 0x08);		/* ZAP_CACHE */
		writel(imask[i], m + 0x1c);
		writel(gate[i] | BIT(31), m + 0x24);
		writel(0, m + 0x08);		/* ENABLE_PAGING */
		ret = readl_poll_timeout(m + 0x04, v, v & BIT(0), 10, 1000);
		pr_info("rstprobe: core%d mmu%d reprogrammed: %s\n", core, i,
			ret ? "paging enable timed out" : "ok");
	}
	dump("restored");
	ret = -EAGAIN;	/* never stay loaded */

out_unmap:
	if (cru)
		iounmap(cru);
	if (fn)
		iounmap(fn);
	if (mmu)
		iounmap(mmu);
	pm_runtime_put(dev);
out_dev:
	put_device(dev);
	return ret;
}
module_init(rstprobe_init);

MODULE_DESCRIPTION("RK3588 vdec core reset vs IOMMU register probe (measurement only)");
MODULE_LICENSE("GPL");
