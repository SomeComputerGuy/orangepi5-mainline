// SPDX-License-Identifier: GPL-2.0
/* Debug-only: dump / write MMIO words, then fail init so it unloads itself. */
#include <linux/module.h>
#include <linux/io.h>

static unsigned long addr;
static unsigned int len = 0x20;
static unsigned long waddr;
static unsigned int wval;
module_param(addr, ulong, 0);
module_param(len, uint, 0);
module_param(waddr, ulong, 0);
module_param(wval, uint, 0);

static int __init regpeek_init(void)
{
	void __iomem *p;
	unsigned int i;

	if (waddr) {
		p = ioremap(waddr & ~0xfffUL, 0x1000);
		if (!p)
			return -ENOMEM;
		pr_info("regpeek: %08lx: %08x -> %08x\n", waddr,
			readl(p + (waddr & 0xfff)), wval);
		writel(wval, p + (waddr & 0xfff));
		pr_info("regpeek: %08lx: now %08x\n", waddr, readl(p + (waddr & 0xfff)));
		iounmap(p);
	}
	if (addr) {
		p = ioremap(addr, len);
		if (!p)
			return -ENOMEM;
		for (i = 0; i < len; i += 16)
			pr_info("regpeek: %08lx: %08x %08x %08x %08x\n", addr + i,
				readl(p + i), readl(p + i + 4), readl(p + i + 8), readl(p + i + 12));
		iounmap(p);
	}
	return -EAGAIN;
}
module_init(regpeek_init);
MODULE_LICENSE("GPL");
