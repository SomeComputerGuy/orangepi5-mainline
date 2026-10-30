import sys
d=sys.argv[1]
def patch(p, reps):
    s=open(p).read()
    for a,b in reps:
        assert s.count(a)==1, (p,a); s=s.replace(a,b)
    open(p,'w').write(s)
patch(d+'/rkvdec-ccu.c',[('''void rkvdec_ccu_disconnect(struct rkvdec_ccu *ccu, struct rkvdec_core *core)
{
	writel(RKVDEC_CCU_CORE_SET(core->ccu_port), ccu->regs + RKVDEC_CCU_CORE_IDLE);
}''','''void rkvdec_ccu_disconnect(struct rkvdec_ccu *ccu, struct rkvdec_core *core)
{
	/*
	 * Take the core out of CCU mode, so that it doesn't pick its task up
	 * again when the reset releases it, and force it idle in the CCU.
	 */
	writel(0, core->link + VDPU381_LINK_CTRL);
	writel(BIT(core->ccu_port + 16), ccu->regs + RKVDEC_CCU_CORE_WORK);
	writel(RKVDEC_CCU_CORE_SET(core->ccu_port), ccu->regs + RKVDEC_CCU_CORE_IDLE);
}''')])
p=d+'/rkvdec.c'; s=open(p).read()
a='''	writel(VDPU381_SOFT_RESET_EN, core->regs + VDPU381_REG_IMPORTANT_EN);
	ret = readl_poll_timeout_atomic(core->regs + VDPU381_REG_STA_INT, status,'''
b='''	/* Stop the core: no start bit, no interrupt, before the soft reset. */
	writel(0, core->regs + VDPU381_REG_DEC_E);
	writel(VDPU381_SOFT_RESET_EN, core->regs + VDPU381_REG_IMPORTANT_EN);
	ret = readl_poll_timeout_atomic(core->regs + VDPU381_REG_STA_INT, status,'''
assert s.count(a)==1; s=s.replace(a,b)
a='''	if (core->resets) {
		if (!reset_control_assert(core->resets)) {
			udelay(5);
			if (reset_control_deassert(core->resets))
				dev_err(core->dev, "failed to deassert the resets\\n");
		}
	}
'''
b=a+'''	writel(0, core->regs + VDPU381_REG_STA_INT);
'''
assert s.count(a)==1; s=s.replace(a,b)
open(p,'w').write(s)
