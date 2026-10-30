// SPDX-License-Identifier: GPL-2.0
/*
 * Debug-only: keep a genpd power domain on across system suspend by putting
 * one of its devices in the wakeup path. genpd_finish_suspend() leaves a
 * GENPD_FLAG_ACTIVE_WAKEUP domain (RK3588 "pcie" is one) powered when a
 * device in it is on the wakeup path. Used to test whether RK3588 PD_PCIE
 * powering off in suspend_noirq causes the s2idle resume wedge.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm_wakeup.h>

static char devname[64] = "fc900000.iommu";
module_param_string(devname, devname, sizeof(devname), 0444);

static struct device *dev;

static int __init pdk_init(void)
{
	dev = bus_find_device_by_name(&platform_bus_type, NULL, devname);
	if (!dev)
		return -ENODEV;
	device_set_wakeup_capable(dev, true);
	device_wakeup_enable(dev);
	pr_info("pd_keep2: %s may_wakeup=%d pm_domain=%s\n", devname,
		device_may_wakeup(dev), dev->pm_domain ? "yes" : "no");
	return 0;
}

static void __exit pdk_exit(void)
{
	device_wakeup_disable(dev);
	device_set_wakeup_capable(dev, false);
	put_device(dev);
}

module_init(pdk_init);
module_exit(pdk_exit);
MODULE_DESCRIPTION("debug: keep a device's power domain on across system suspend");
MODULE_LICENSE("GPL");
