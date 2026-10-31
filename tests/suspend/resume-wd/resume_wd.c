// SPDX-License-Identifier: GPL-2.0
/*
 * Debug-only "resume watchdog": a dummy platform device whose noirq
 * resume callback arms a timer.  If PM_POST_SUSPEND has not been seen
 * @timeout seconds later, dump the tail of the kernel log (so that
 * pm_print_times can be collected with a quiet console), NMI
 * backtraces of all CPUs and the blocked tasks.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/suspend.h>
#include <linux/timer.h>
#include <linux/percpu.h>
#include <linux/atomic.h>
#include <linux/sysrq.h>
#include <linux/printk.h>
#include <linux/kmsg_dump.h>
#include <linux/slab.h>

static unsigned int timeout = 6;
module_param(timeout, uint, 0644);
static unsigned int lines = 250;
module_param(lines, uint, 0444);

#define LINE_SZ 200
static char *ring;
static struct platform_device *rwd_pdev;

static void dump_log_tail(void)
{
	struct kmsg_dump_iter iter;
	unsigned int n = 0, i, start;
	size_t len;

	kmsg_dump_rewind(&iter);
	while (kmsg_dump_get_line(&iter, false, ring + (n % lines) * LINE_SZ,
				  LINE_SZ - 1, &len)) {
		ring[(n % lines) * LINE_SZ + len] = '\0';
		n++;
	}
	start = n > lines ? n - lines : 0;
	pr_emerg("resume_wd: ---- last %u log lines ----\n", n - start);
	for (i = start; i < n; i++)
		pr_emerg("rwd| %s", ring + (i % lines) * LINE_SZ);
	pr_emerg("resume_wd: ---- end of log ----\n");
}

static atomic_t rwd_once;
static bool rwd_armed;
static DEFINE_PER_CPU(struct timer_list, rwd_timer);

static void rwd_timer_fn(struct timer_list *t)
{
	if (!READ_ONCE(rwd_armed) || atomic_xchg(&rwd_once, 1))
		return;
	console_verbose();
	pr_emerg("resume_wd: resume not finished %us after noirq resume (CPU%d)\n",
		 timeout, smp_processor_id());
	dump_log_tail();
	handle_sysrq('l');
	handle_sysrq('w');
	panic("resume_wd: stuck system resume");
}

static int rwd_resume_noirq(struct device *dev)
{
	int cpu;

	atomic_set(&rwd_once, 0);
	WRITE_ONCE(rwd_armed, true);
	for_each_online_cpu(cpu) {
		struct timer_list *t = per_cpu_ptr(&rwd_timer, cpu);

		t->expires = jiffies + timeout * HZ + cpu;
		add_timer_on(t, cpu);
	}
	return 0;
}

static void rwd_disarm(void)
{
	int cpu;

	WRITE_ONCE(rwd_armed, false);
	for_each_possible_cpu(cpu)
		timer_delete_sync(per_cpu_ptr(&rwd_timer, cpu));
}

static const struct dev_pm_ops rwd_pm_ops = {
	NOIRQ_SYSTEM_SLEEP_PM_OPS(NULL, rwd_resume_noirq)
};

static struct platform_driver rwd_driver = {
	.driver = { .name = "resume_wd", .pm = &rwd_pm_ops },
};

static int resume_wd_pm(struct notifier_block *nb, unsigned long ev, void *p)
{
	if (ev == PM_POST_SUSPEND)
		rwd_disarm();
	return NOTIFY_DONE;
}

static struct notifier_block resume_wd_nb = { .notifier_call = resume_wd_pm };

static int __init resume_wd_init(void)
{
	int ret;

	int cpu;

	for_each_possible_cpu(cpu)
		timer_setup(per_cpu_ptr(&rwd_timer, cpu), rwd_timer_fn, TIMER_PINNED);

	ring = kcalloc(lines, LINE_SZ, GFP_KERNEL);
	if (!ring)
		return -ENOMEM;
	ret = platform_driver_register(&rwd_driver);
	if (ret)
		goto err_free;
	rwd_pdev = platform_device_register_simple("resume_wd", -1, NULL, 0);
	if (IS_ERR(rwd_pdev)) {
		ret = PTR_ERR(rwd_pdev);
		goto err_drv;
	}
	ret = register_pm_notifier(&resume_wd_nb);
	if (ret)
		goto err_dev;
	return 0;
err_dev:
	platform_device_unregister(rwd_pdev);
err_drv:
	platform_driver_unregister(&rwd_driver);
err_free:
	kfree(ring);
	return ret;
}

static void __exit resume_wd_exit(void)
{
	unregister_pm_notifier(&resume_wd_nb);
	rwd_disarm();
	platform_device_unregister(rwd_pdev);
	platform_driver_unregister(&rwd_driver);
	kfree(ring);
}

module_init(resume_wd_init);
module_exit(resume_wd_exit);
MODULE_DESCRIPTION("debug: report stuck system resume");
MODULE_LICENSE("GPL");
