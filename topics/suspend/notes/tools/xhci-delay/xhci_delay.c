// SPDX-License-Identifier: GPL-2.0
/*
 * Debug-only: busy-wait @delay_ms on entry to @sym (default xhci_halt), but
 * only while a system suspend/resume transition is in progress. Used to show
 * where in xhci_resume() the slow serial console was hiding the RK3588 wedge.
 */
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/delay.h>
#include <linux/suspend.h>
#include <linux/atomic.h>

static char sym[64] = "xhci_halt";
module_param_string(sym, sym, sizeof(sym), 0444);
static unsigned int delay_ms = 20;
module_param(delay_ms, uint, 0644);

static bool in_transition;
static atomic_t hits;

static int pre(struct kprobe *p, struct pt_regs *regs)
{
	if (READ_ONCE(in_transition)) {
		atomic_inc(&hits);
		mdelay(READ_ONCE(delay_ms));
	}
	return 0;
}

static struct kprobe kp = { .pre_handler = pre };

static int xd_pm(struct notifier_block *nb, unsigned long ev, void *p)
{
	if (ev == PM_SUSPEND_PREPARE) {
		atomic_set(&hits, 0);
		WRITE_ONCE(in_transition, true);
		pr_info("xhci_delay: armed %u ms at %s\n", delay_ms, sym);
	} else if (ev == PM_POST_SUSPEND) {
		WRITE_ONCE(in_transition, false);
		pr_info("xhci_delay: done, %d delays at %s\n", atomic_read(&hits), sym);
	}
	return NOTIFY_DONE;
}

static struct notifier_block xd_nb = { .notifier_call = xd_pm };

static int __init xd_init(void)
{
	int ret;

	kp.symbol_name = sym;
	ret = register_kprobe(&kp);
	if (ret)
		return ret;
	ret = register_pm_notifier(&xd_nb);
	if (ret)
		unregister_kprobe(&kp);
	return ret;
}

static void __exit xd_exit(void)
{
	unregister_pm_notifier(&xd_nb);
	unregister_kprobe(&kp);
}

module_init(xd_init);
module_exit(xd_exit);
MODULE_DESCRIPTION("debug: delay at a kprobe during system suspend/resume");
MODULE_LICENSE("GPL");
