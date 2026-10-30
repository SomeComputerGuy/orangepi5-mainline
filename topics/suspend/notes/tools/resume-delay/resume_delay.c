// SPDX-License-Identifier: GPL-2.0
/*
 * Debug-only: busy-wait @delay_ms before selected device PM callbacks, to
 * reproduce the "slow serial console" timing (~20 ms per device with
 * pm_print_times at 115200 baud) without a console, and bisect which
 * device(s) need the gap.
 *
 * Parameters (all writable at runtime under /sys/module/resume_delay/parameters):
 *   events   bitmask: 1 = suspend side (PM_EVENT_SUSPEND), 2 = resume side
 *            (PM_EVENT_RESUME); 0 disables
 *   phases   0 = normal phase only (skip "late"/"early"/"noirq" callbacks),
 *            1 = all phases
 *   match    comma-separated substrings of dev_name() of the device or any
 *            of its ancestors (selects a subtree), or of the driver name;
 *            empty = every device
 *   invert   1 = delay devices that do NOT match
 *   delay_ms busy-wait per matching callback (tracepoint probes run with
 *            preemption disabled, so this cannot sleep)
 */
#include <linux/module.h>
#include <linux/tracepoint.h>
#include <linux/device.h>
#include <linux/delay.h>
#include <linux/pm.h>
#include <linux/suspend.h>
#include <linux/string.h>
#include <linux/atomic.h>

static unsigned int events = 3;
module_param(events, uint, 0644);
static unsigned int phases;
module_param(phases, uint, 0644);
static unsigned int invert;
module_param(invert, uint, 0644);
static unsigned int delay_ms = 20;
module_param(delay_ms, uint, 0644);
static char match[512];
module_param_string(match, match, sizeof(match), 0644);

static atomic_t hits_suspend, hits_resume;
static struct tracepoint *tp_start;

static bool name_matches(const char *name, const char *list)
{
	const char *p = list;
	char tok[64];

	while (*p) {
		const char *e = strchrnul(p, ',');
		size_t n = e - p;

		while (n && (p[n - 1] == '\n' || p[n - 1] == ' '))
			n--;
		if (n && n < sizeof(tok)) {
			memcpy(tok, p, n);
			tok[n] = '\0';
			if (strstr(name, tok))
				return true;
		}
		p = *e ? e + 1 : e;
	}
	return false;
}

static bool dev_selected(struct device *dev)
{
	bool m;

	struct device *d;

	if (!match[0] || match[0] == '\n') {
		m = true;
	} else {
		/* match the device, its driver, or any ancestor (subtree) */
		m = name_matches(dev_driver_string(dev), match);
		for (d = dev; d && !m; d = d->parent)
			m = name_matches(dev_name(d), match);
	}
	return invert ? !m : m;
}

static void probe_start(void *data, struct device *dev, const char *pm_ops,
			int event)
{
	unsigned int ev = READ_ONCE(events);
	bool resume;

	if (event & PM_EVENT_RESUME)
		resume = true;
	else if (event & PM_EVENT_SUSPEND)
		resume = false;
	else
		return;
	if (!(ev & (resume ? 2 : 1)))
		return;
	if (!READ_ONCE(phases) && pm_ops &&
	    (strstr(pm_ops, "noirq") || strstr(pm_ops, "early") ||
	     strstr(pm_ops, "late")))
		return;
	if (!dev_selected(dev))
		return;
	atomic_inc(resume ? &hits_resume : &hits_suspend);
	mdelay(READ_ONCE(delay_ms));
}

static int rd_pm(struct notifier_block *nb, unsigned long ev, void *p)
{
	if (ev == PM_SUSPEND_PREPARE) {
		atomic_set(&hits_suspend, 0);
		atomic_set(&hits_resume, 0);
		pr_info("resume_delay: armed events=%u phases=%u invert=%u delay_ms=%u match='%s'\n",
			events, phases, invert, delay_ms, match);
	} else if (ev == PM_POST_SUSPEND) {
		pr_info("resume_delay: done, delayed %d suspend and %d resume callbacks\n",
			atomic_read(&hits_suspend), atomic_read(&hits_resume));
	}
	return NOTIFY_DONE;
}

static struct notifier_block rd_nb = { .notifier_call = rd_pm };

static void find_tp(struct tracepoint *tp, void *priv)
{
	if (!strcmp(tp->name, "device_pm_callback_start"))
		tp_start = tp;
}

static int __init resume_delay_init(void)
{
	int ret;

	for_each_kernel_tracepoint(find_tp, NULL);
	if (!tp_start)
		return -ENOENT;
	ret = tracepoint_probe_register(tp_start, probe_start, NULL);
	if (ret)
		return ret;
	ret = register_pm_notifier(&rd_nb);
	if (ret)
		tracepoint_probe_unregister(tp_start, probe_start, NULL);
	return ret;
}

static void __exit resume_delay_exit(void)
{
	unregister_pm_notifier(&rd_nb);
	tracepoint_probe_unregister(tp_start, probe_start, NULL);
	tracepoint_synchronize_unregister();
}

module_init(resume_delay_init);
module_exit(resume_delay_exit);
MODULE_DESCRIPTION("debug: inject delays before device PM callbacks");
MODULE_LICENSE("GPL");
