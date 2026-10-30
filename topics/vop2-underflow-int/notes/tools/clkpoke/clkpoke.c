// SPDX-License-Identifier: GPL-2.0
/* Debug-only: set/show the rate of a VOP2 clock by DT clock name, then fail init. */
#include <linux/clk.h>
#include <linux/clk-provider.h>
#include <linux/module.h>
#include <linux/of.h>

static char *name = "aclk";
static unsigned long rate;
module_param(name, charp, 0);
module_param(rate, ulong, 0);

static int __init clkpoke_init(void)
{
	struct device_node *np;
	struct clk *clk;

	np = of_find_compatible_node(NULL, NULL, "rockchip,rk3588-vop");
	if (!np)
		return -ENODEV;
	clk = of_clk_get_by_name(np, name);
	of_node_put(np);
	if (IS_ERR(clk))
		return PTR_ERR(clk);
	pr_info("clkpoke: %s = %lu (parent %s)\n", name, clk_get_rate(clk),
		__clk_get_name(clk_get_parent(clk)));
	if (rate) {
		int ret = clk_set_rate(clk, rate);

		pr_info("clkpoke: set %s %lu -> ret %d, now %lu (parent %s)\n", name, rate,
			ret, clk_get_rate(clk), __clk_get_name(clk_get_parent(clk)));
	}
	clk_put(clk);
	return -EAGAIN;
}
module_init(clkpoke_init);
MODULE_LICENSE("GPL");
