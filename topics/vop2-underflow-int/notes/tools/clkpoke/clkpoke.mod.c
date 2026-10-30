#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
	.arch = MODULE_ARCH_INIT,
};



static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0xef3d73a6, "of_find_compatible_node" },
	{ 0x62213a9b, "of_clk_get_by_name" },
	{ 0xacfee59a, "of_node_put" },
	{ 0xa0928e7c, "clk_get_rate" },
	{ 0x352e61f6, "clk_get_parent" },
	{ 0xbd8a80e3, "__clk_get_name" },
	{ 0xe8213e80, "_printk" },
	{ 0x71a97e4a, "clk_set_rate" },
	{ 0x33d0c686, "clk_put" },
	{ 0x7b875885, "param_ops_ulong" },
	{ 0x7b875885, "param_ops_charp" },
	{ 0x8c537242, "module_layout" },
};

static const u32 ____version_ext_crcs[]
__used __section("__version_ext_crcs") = {
	0xef3d73a6,
	0x62213a9b,
	0xacfee59a,
	0xa0928e7c,
	0x352e61f6,
	0xbd8a80e3,
	0xe8213e80,
	0x71a97e4a,
	0x33d0c686,
	0x7b875885,
	0x7b875885,
	0x8c537242,
};
static const char ____version_ext_names[]
__used __section("__version_ext_names") =
	"of_find_compatible_node\0"
	"of_clk_get_by_name\0"
	"of_node_put\0"
	"clk_get_rate\0"
	"clk_get_parent\0"
	"__clk_get_name\0"
	"_printk\0"
	"clk_set_rate\0"
	"clk_put\0"
	"param_ops_ulong\0"
	"param_ops_charp\0"
	"module_layout\0"
;

MODULE_INFO(depends, "");


MODULE_INFO(srcversion, "1B966E8CFAA87363AE53926");
