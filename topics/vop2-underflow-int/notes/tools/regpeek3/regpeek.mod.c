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
	{ 0xc429d7ce, "__tracepoint_rwmmio_read" },
	{ 0x1688fc48, "log_read_mmio" },
	{ 0xc429d7ce, "__tracepoint_rwmmio_post_read" },
	{ 0xb06660af, "log_post_read_mmio" },
	{ 0x3239fbdb, "arm64_use_ng_mappings" },
	{ 0xe4de56b4, "__ubsan_handle_load_invalid_value" },
	{ 0x54418698, "__ioremap_prot" },
	{ 0xe8213e80, "_printk" },
	{ 0xc429d7ce, "__tracepoint_rwmmio_write" },
	{ 0xf2a40031, "log_write_mmio" },
	{ 0xc429d7ce, "__tracepoint_rwmmio_post_write" },
	{ 0xf2a40031, "log_post_write_mmio" },
	{ 0x12ad300e, "iounmap" },
	{ 0x7b875885, "param_ops_uint" },
	{ 0x7b875885, "param_ops_ulong" },
	{ 0x8c537242, "module_layout" },
};

static const u32 ____version_ext_crcs[]
__used __section("__version_ext_crcs") = {
	0xc429d7ce,
	0x1688fc48,
	0xc429d7ce,
	0xb06660af,
	0x3239fbdb,
	0xe4de56b4,
	0x54418698,
	0xe8213e80,
	0xc429d7ce,
	0xf2a40031,
	0xc429d7ce,
	0xf2a40031,
	0x12ad300e,
	0x7b875885,
	0x7b875885,
	0x8c537242,
};
static const char ____version_ext_names[]
__used __section("__version_ext_names") =
	"__tracepoint_rwmmio_read\0"
	"log_read_mmio\0"
	"__tracepoint_rwmmio_post_read\0"
	"log_post_read_mmio\0"
	"arm64_use_ng_mappings\0"
	"__ubsan_handle_load_invalid_value\0"
	"__ioremap_prot\0"
	"_printk\0"
	"__tracepoint_rwmmio_write\0"
	"log_write_mmio\0"
	"__tracepoint_rwmmio_post_write\0"
	"log_post_write_mmio\0"
	"iounmap\0"
	"param_ops_uint\0"
	"param_ops_ulong\0"
	"module_layout\0"
;

MODULE_INFO(depends, "");


MODULE_INFO(srcversion, "25308C8DBC662A3251EAB6B");
