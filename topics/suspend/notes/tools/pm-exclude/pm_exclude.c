// SPDX-License-Identifier: GPL-2.0
/*
 * Debug-only: exclude a list of devices from system suspend/resume by making
 * them PM syscore devices (the PM core then skips all of their system sleep
 * callbacks, and genpd never counts them as suspended). Used to bisect which
 * device's resume wedges the RK3588 after a fast s2idle.
 *
 *   insmod pm_exclude.ko devs=fe210000.sata,fee00000.phy[,...]
 * Names are matched exactly against the platform and AMBA buses; with prefix=1 every
 * platform device whose name starts with one of the entries is excluded,
 * except the ones listed in skip= (e.g. the watchdog, which must stop).
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/amba/bus.h>
#include <linux/pm.h>
#include <linux/string.h>
#include <linux/slab.h>

#define MAX_DEVS 256

static char devs[1024];
module_param_string(devs, devs, sizeof(devs), 0444);
static bool prefix;
module_param(prefix, bool, 0444);
static char skip[512];
module_param_string(skip, skip, sizeof(skip), 0444);

static struct device *excluded[MAX_DEVS];
static int nr_excluded;

static int match_prefix(struct device *dev, const void *data)
{
	const char *p = data;

	return !strncmp(dev_name(dev), p, strlen(p));
}

static bool skipped(const char *name)
{
	const char *p = skip;
	size_t n = strlen(name);

	while ((p = strstr(p, name))) {
		if ((p == skip || p[-1] == ',') && (p[n] == ',' || !p[n]))
			return true;
		p += n;
	}
	return false;
}

static void exclude(struct device *dev)
{
	if (skipped(dev_name(dev))) {
		pr_info("pm_exclude: %s skipped\n", dev_name(dev));
		put_device(dev);
		return;
	}
	if (nr_excluded >= MAX_DEVS) {
		put_device(dev);
		return;
	}
	dev_pm_syscore_device(dev, true);
	excluded[nr_excluded++] = dev;
	pr_info("pm_exclude: %s excluded from system suspend\n", dev_name(dev));
}

static int __init pmx_init(void)
{
	char *buf, *s, *tok;
	struct device *dev, *start;

	buf = kstrdup(devs, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;
	s = buf;
	while ((tok = strsep(&s, ",")) != NULL) {
		tok = strim(tok);
		if (!*tok)
			continue;
		if (!prefix) {
			dev = bus_find_device_by_name(&platform_bus_type, NULL, tok);
			if (!dev)
				dev = bus_find_device_by_name(&amba_bustype, NULL, tok);
			if (dev)
				exclude(dev);
			else
				pr_warn("pm_exclude: %s not found\n", tok);
			continue;
		}
		start = NULL;
		while ((dev = bus_find_device(&platform_bus_type, start, tok,
					      match_prefix))) {
			put_device(start);
			start = dev;
			get_device(dev);
			exclude(dev);
		}
		put_device(start);
	}
	kfree(buf);
	pr_info("pm_exclude: %d device(s) excluded\n", nr_excluded);
	return nr_excluded ? 0 : -ENODEV;
}

static void __exit pmx_exit(void)
{
	while (nr_excluded--) {
		dev_pm_syscore_device(excluded[nr_excluded], false);
		put_device(excluded[nr_excluded]);
	}
}

module_init(pmx_init);
module_exit(pmx_exit);
MODULE_DESCRIPTION("debug: exclude devices from system suspend");
MODULE_LICENSE("GPL");
