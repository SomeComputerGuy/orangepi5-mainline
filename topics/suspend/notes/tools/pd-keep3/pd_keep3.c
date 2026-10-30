// SPDX-License-Identifier: GPL-2.0
/*
 * Debug-only: exclude a device from system suspend (PM syscore device), so
 * genpd never counts it as suspended and its power domain stays on even if
 * the domain is not ACTIVE_WAKEUP (RK3588 "gmac").
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pm.h>

static char devname[64] = "fe1c0000.ethernet";
module_param_string(devname, devname, sizeof(devname), 0444);

static struct device *dev;

static int __init pdk3_init(void)
{
	dev = bus_find_device_by_name(&platform_bus_type, NULL, devname);
	if (!dev)
		return -ENODEV;
	dev_pm_syscore_device(dev, true);
	pr_info("pd_keep3: %s excluded from system suspend\n", devname);
	return 0;
}

static void __exit pdk3_exit(void)
{
	dev_pm_syscore_device(dev, false);
	put_device(dev);
}

module_init(pdk3_init);
module_exit(pdk3_exit);
MODULE_DESCRIPTION("debug: exclude a device from system suspend");
MODULE_LICENSE("GPL");
