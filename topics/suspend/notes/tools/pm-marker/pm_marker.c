// SPDX-License-Identifier: GPL-2.0
/*
 * Debug-only: per-CPU "where am I" markers for system resume, written to a
 * non-cacheable DRAM page (dma_alloc_coherent) so they reach memory before a
 * watchdog reset and cost no console time. The page's physical address is
 * printed when armed; after the reset, load with dump=1 phys=<addr> to read
 * the previous boot's slots from that (now unowned, read-only) RAM page.
 * Ordinary RAM does not reliably survive the reset and next boot. With the
 * debug overlay (tools/dt/rk3588-opi5-debug-ramoops.dtso) use the reserved,
 * unmapped area instead: phys=0x30200000 arms and dumps that region.
 *
 * Each CPU slot records the device PM callback it is in (tracepoint
 * device_pm_callback_start/end) and the last kprobe it hit (xHCI resume
 * steps). Load with dump=1 after a wedge to print the previous boot's slots.
 */
#include <linux/module.h>
#include <linux/io.h>
#include <linux/kprobes.h>
#include <linux/tracepoint.h>
#include <linux/device.h>
#include <linux/suspend.h>
#include <linux/smp.h>
#include <linux/string.h>
#include <linux/pm.h>
#include <linux/dma-mapping.h>
#include <linux/platform_device.h>
#include <linux/sizes.h>
#include <linux/mm.h>
#include <linux/memblock.h>

static unsigned long phys;
module_param(phys, ulong, 0444);
static bool dump;
module_param(dump, bool, 0444);

#define MAGIC		0x504d4b31	/* "PMK1" */
#define NSLOT		8
#define SLOT_SZ		256
#define BUF_SZ		SZ_64K	/* > 1 page: comes from CMA, a fixed region not used early in boot */
struct slot {
	u32 magic;
	u32 seq;		/* bumped on every update */
	u32 event;		/* PM event of the current callback */
	u32 in_cb;		/* 1 between callback start and end */
	u32 kp_seq;
	u32 transition;		/* global: 1 suspend, 2 resume begun (s2idle wake) */
	char dev[64];		/* device of the current/last callback */
	char ops[32];
	char kp[32];		/* last kprobe hit */
	char done[64];		/* last device whose callback ended on this CPU */
};

static void __iomem *mem;
static void *cpu_addr;
static dma_addr_t dma_handle;
static struct platform_device *pdev;

static struct slot __iomem *slot_of(int cpu)
{
	return mem + cpu * SLOT_SZ;
}

static void put_str(char __iomem *dst, const char *s, size_t n)
{
	char buf[64] = {};

	strscpy(buf, s ? s : "", min(n, sizeof(buf)));
	memcpy_toio(dst, buf, n);
}

static void probe_start(void *data, struct device *dev, const char *pm_ops, int event)
{
	struct slot __iomem *s = slot_of(raw_smp_processor_id());

	put_str(s->dev, dev_name(dev), sizeof(s->dev));
	put_str(s->ops, pm_ops, sizeof(s->ops));
	writel(event, &s->event);
	writel(1, &s->in_cb);
	writel(readl(&s->seq) + 1, &s->seq);
}

static void probe_end(void *data, struct device *dev, int error)
{
	struct slot __iomem *s = slot_of(raw_smp_processor_id());

	put_str(s->done, dev_name(dev), sizeof(s->done));
	writel(0, &s->in_cb);
	writel(readl(&s->seq) + 1, &s->seq);
}

static const char * const kp_syms[] = {
	"xhci_resume", "xhci_halt", "xhci_reset", "xhci_init", "xhci_run",
	"xhci_handshake", "usb_root_hub_lost_power", "usb_hcd_resume_root_hub",
	"xhci_bus_resume", "xhci_hub_control",
};
static struct kprobe kps[ARRAY_SIZE(kp_syms)];

static int kp_pre(struct kprobe *p, struct pt_regs *regs)
{
	struct slot __iomem *s = slot_of(raw_smp_processor_id());

	put_str(s->kp, p->symbol_name, sizeof(s->kp));
	writel(readl(&s->kp_seq) + 1, &s->kp_seq);
	return 0;
}

static int pmk_pm(struct notifier_block *nb, unsigned long ev, void *p)
{
	int cpu;

	for (cpu = 0; cpu < NSLOT; cpu++)
		writel(ev == PM_SUSPEND_PREPARE ? 1 : 0, &slot_of(cpu)->transition);
	return NOTIFY_DONE;
}

static struct notifier_block pmk_nb = { .notifier_call = pmk_pm };
static struct tracepoint *tp_start, *tp_end;

static void find_tp(struct tracepoint *tp, void *priv)
{
	if (!strcmp(tp->name, "device_pm_callback_start"))
		tp_start = tp;
	else if (!strcmp(tp->name, "device_pm_callback_end"))
		tp_end = tp;
}

static void dump_slots(void)
{
	struct slot *old;
	int cpu;

	if (!phys || !PAGE_ALIGNED(phys)) {
		pr_info("pm_marker: dump needs phys=<page-aligned address>\n");
		return;
	}
	/* plain system RAM: a read-only look at the previous boot's page */
	old = memremap(phys, BUF_SZ, page_is_ram(PHYS_PFN(phys)) ?
		       MEMREMAP_WB : MEMREMAP_WC);
	if (!old) {
		pr_info("pm_marker: cannot map %#lx\n", phys);
		return;
	}
	for (cpu = 0; cpu < NSLOT; cpu++) {
		struct slot sl = *(struct slot *)((char *)old + cpu * SLOT_SZ);

		if (sl.magic != MAGIC) {
			pr_info("pm_marker: cpu%d: no valid record\n", cpu);
			continue;
		}
		sl.dev[63] = sl.ops[31] = sl.kp[31] = sl.done[63] = '\0';
		pr_info("pm_marker: cpu%d: transition=%u seq=%u %s cb dev='%s' ops='%s' event=0x%x last-done='%s' kp='%s' kp_seq=%u\n",
			cpu, sl.transition, sl.seq, sl.in_cb ? "IN" : "after", sl.dev, sl.ops,
			sl.event, sl.done, sl.kp, sl.kp_seq);
	}
	memunmap(old);
}

static int __init pmk_init(void)
{
	int cpu, i, ret;

	if (dump)
		dump_slots();
	if (phys && !page_is_ram(PHYS_PFN(phys))) {
		/* reserved no-map region from the debug overlay */
		cpu_addr = memremap(phys, BUF_SZ, MEMREMAP_WC);
		if (!cpu_addr)
			return -ENOMEM;
		mem = (void __iomem *)cpu_addr;
		dma_handle = phys;
		goto arm;
	}
	pdev = platform_device_register_simple("pm_marker", -1, NULL, 0);
	if (IS_ERR(pdev))
		return PTR_ERR(pdev);
	ret = dma_coerce_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64));
	if (ret)
		goto err_pdev;
	cpu_addr = dma_alloc_coherent(&pdev->dev, BUF_SZ, &dma_handle, GFP_KERNEL);
	if (!cpu_addr) {
		ret = -ENOMEM;
		goto err_pdev;
	}
	mem = (void __iomem *)cpu_addr;
arm:
	for (cpu = 0; cpu < NSLOT; cpu++) {
		memset_io(slot_of(cpu), 0, SLOT_SZ);
		writel(MAGIC, &slot_of(cpu)->magic);
	}
	for_each_kernel_tracepoint(find_tp, NULL);
	if (!tp_start || !tp_end) {
		ret = -ENOENT;
		goto err_unmap;
	}
	ret = tracepoint_probe_register(tp_start, probe_start, NULL);
	if (ret)
		goto err_unmap;
	ret = tracepoint_probe_register(tp_end, probe_end, NULL);
	if (ret)
		goto err_tp1;
	for (i = 0; i < ARRAY_SIZE(kps); i++) {
		kps[i].symbol_name = kp_syms[i];
		kps[i].pre_handler = kp_pre;
		if (register_kprobe(&kps[i]))
			pr_warn("pm_marker: no kprobe for %s\n", kp_syms[i]);
	}
	register_pm_notifier(&pmk_nb);
	pr_info("pm_marker: armed, phys=%#llx\n", (unsigned long long)dma_handle);
	return 0;

err_tp1:
	tracepoint_probe_unregister(tp_start, probe_start, NULL);
err_unmap:
	if (pdev)
		dma_free_coherent(&pdev->dev, BUF_SZ, cpu_addr, dma_handle);
	else
		memunmap(cpu_addr);
err_pdev:
	if (pdev)
		platform_device_unregister(pdev);
	return ret;
}

static void __exit pmk_exit(void)
{
	int i;

	unregister_pm_notifier(&pmk_nb);
	for (i = 0; i < ARRAY_SIZE(kps); i++)
		if (kps[i].addr)
			unregister_kprobe(&kps[i]);
	tracepoint_probe_unregister(tp_end, probe_end, NULL);
	tracepoint_probe_unregister(tp_start, probe_start, NULL);
	tracepoint_synchronize_unregister();
	if (pdev) {
		dma_free_coherent(&pdev->dev, BUF_SZ, cpu_addr, dma_handle);
		platform_device_unregister(pdev);
	} else {
		memunmap(cpu_addr);
	}
}

module_init(pmk_init);
module_exit(pmk_exit);
MODULE_DESCRIPTION("debug: per-CPU resume markers in SRAM");
MODULE_LICENSE("GPL");
