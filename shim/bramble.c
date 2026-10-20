/*
 * bramble (Pixel 4a 5G) probe, no XNU.
 *
 * Milestone 1 (display, answered): ABL leaves the command-mode sofef01 panel
 * on autorefresh, so plain writes to the SSPP0 buffer reach the panel. The
 * probe still logs the scanout SSPP, CTL state and self-changing MDP words.
 * Kicking CTL_START on top of autorefresh blanked the top of the panel.
 *
 * Milestone 2 (watchdog): two boots reset ~11 s in (bootreason watchdog)
 * although the probe wrote WDT0_RST. Now: log the APSS WDT registers, pet
 * for 6 s, then clear WDT0_EN and stop petting, with a live seconds counter.
 * Where the counter stops is the answer: ~11 = pets do not reach it,
 * ~17 = pets work but EN=0 does not, 60 = both work (then a clean reset).
 * The log also goes into both pstore console zones.
 *
 * Everything runs with the MMU off (Device memory), as in sweet's shim.
 */
#include <stdint.h>
#include "font.h"

/* bramble PVT live FDT, qcom,mdss_mdp: mdp_phys and the sde-*-off cells */
#define MDSS_BASE		0x0ae00000UL
#define MDP_TOP			(MDSS_BASE + 0x1000)
#define CTL(i)			(MDSS_BASE + 0x2000 + 0x200 * (i))
#define PP(i)			(MDSS_BASE + 0x71000 + 0x800 * (i))
#define INTF(i)			(MDSS_BASE + 0x6b000 + 0x800 * (i))	/* 1, 2: DSI */
#define NR_SSPP			5
#define NR_CTL			4

/* sde_hw_sspp.c / sde_hw_ctl.c register offsets */
#define SSPP_SRC_SIZE		0x00
#define SSPP_SRC0_ADDR		0x14
#define SSPP_SRC_YSTRIDE0	0x24
#define SSPP_SRC_FORMAT		0x30
#define SSPP_SRC_UNPACK		0x34
#define SSPP_SRC_OP_MODE	0x38
#define CTL_TOP			0x014
#define CTL_FLUSH		0x018
#define CTL_INTF_ACTIVE		0x0f4

/* reserved-memory cont_splash_region: fallback if no SSPP looks active */
#define SPLASH_BASE		0xa0000000UL
#define SPLASH_SIZE		0x2300000UL
#define PANEL_W			1080
#define PANEL_H			2340

/* ramoops: 20 dump records of 0x20000, then the 1 MiB console zone */
#define RAMOOPS_CONSOLE		(0xb7e41000UL + 0x280000)
#define ALT_RAMOOPS_CONSOLE	(0xb8241000UL + 0x280000)
#define RAMOOPS_ZONE_SIZE	0x100000UL
#define PERSISTENT_RAM_SIG	0x43474244U	/* "DBGC" */

/* APSS watchdog, left armed by ABL: bark after 11 s (qcom,bark-time), then bite */
#define WDT_BASE		0x17c10000UL
#define WDT_RST			(WDT_BASE + 0x04)	/* msm_watchdog.c WDT0_* */
#define WDT_EN			(WDT_BASE + 0x08)
#define WDT_STS			(WDT_BASE + 0x0c)
#define WDT_BARK_TIME		(WDT_BASE + 0x10)
#define WDT_BITE_TIME		(WDT_BASE + 0x14)

#define IMEM_RESTART_REASON	0x146ab65cUL	/* qcom,msm-imem@146ab000 restart_reason@65c */
#define RESTART_NORMAL		0x77665501U
#define PSHOLD			0x0c264000UL
#define PSCI_SYSTEM_RESET	0x84000009UL
#define PSCI_SYSTEM_RESET2	0xc4000012UL	/* type 0: warm reset */
#define PSCI_CPU_OFF		0x84000002UL

#define rsr(r) ({ uint64_t _v; __asm__ volatile("mrs %0, " r : "=r"(_v)); _v; })
#define isb() __asm__ volatile("isb" ::: "memory")

static inline uint32_t rd32(uintptr_t a) { return *(volatile uint32_t *)a; }
static inline void wr32(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }

static uint64_t smc(uint64_t fn, uint64_t a1, uint64_t a2, uint64_t a3)
{
	register uint64_t x0 __asm__("x0") = fn;
	register uint64_t x1 __asm__("x1") = a1;
	register uint64_t x2 __asm__("x2") = a2;
	register uint64_t x3 __asm__("x3") = a3;
	__asm__ volatile("smc #0"
			 : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3)
			 :
			 : "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11",
			   "x12", "x13", "x14", "x15", "x16", "x17", "memory");
	return x0;
}

static uint64_t now(void)
{
	isb();
	return rsr("cntpct_el0");
}

/* Pet while the test wants it; drawing and delays call this. */
static int wdt_petting = 1;

static void wdt_pet(void)
{
	if (wdt_petting)
		wr32(WDT_RST, 1);
}

static void delay_ms(unsigned ms)
{
	uint64_t end = now() + rsr("cntfrq_el0") / 1000 * ms;
	while (now() < end)
		wdt_pet();
}

/* ---- log: one text buffer, drawn on the panel and copied to pstore ---- */

static char logbuf[0x4000];
static uint32_t loglen;

static void log_ch(char c)
{
	if (loglen < sizeof(logbuf) - 1)
		logbuf[loglen++] = c;
}

static void log_str(const char *s)
{
	while (*s)
		log_ch(*s++);
}

static void log_hex(uint64_t v, int digits)
{
	static const char hex[] = "0123456789abcdef";
	for (int i = digits - 1; i >= 0; i--)
		log_ch(hex[(v >> (4 * i)) & 0xf]);
}

/* " name=xxxxxxxx" */
static void log_kv(const char *name, uint32_t v)
{
	log_ch(' ');
	log_str(name);
	log_ch('=');
	log_hex(v, 8);
}

static void log_nl(void)
{
	log_ch('\n');
}

static void pstore_put(uintptr_t zone)
{
	volatile uint32_t *hdr = (volatile uint32_t *)zone;
	volatile uint8_t *data = (volatile uint8_t *)(zone + 12);
	uint32_t n = loglen < RAMOOPS_ZONE_SIZE - 12 ? loglen : RAMOOPS_ZONE_SIZE - 12;

	for (uint32_t i = 0; i < n; i++)
		data[i] = logbuf[i];
	hdr[1] = n;	/* start: next write position */
	hdr[2] = n;	/* size: valid bytes */
	hdr[0] = PERSISTENT_RAM_SIG;
	__asm__ volatile("dsb sy" ::: "memory");
}

/* ---- framebuffer: format taken from the scanning SSPP ---- */

static struct {
	uintptr_t base;
	uint32_t w, h, stride, bpp;
} fb;

/* Gray only, so the result does not depend on the unknown component order. */
static void px(uint32_t x, uint32_t y, uint8_t g)
{
	uintptr_t a = fb.base + (uintptr_t)y * fb.stride + (uintptr_t)x * fb.bpp;

	switch (fb.bpp) {
	case 4:
		*(volatile uint32_t *)a = g * 0x01010101U;
		break;
	case 3:
		((volatile uint8_t *)a)[0] = g;
		((volatile uint8_t *)a)[1] = g;
		((volatile uint8_t *)a)[2] = g;
		break;
	case 2:
		*(volatile uint16_t *)a = (uint16_t)((g >> 3) << 11 | (g >> 2) << 5 | (g >> 3));
		break;
	}
}

static void fill(uint8_t g)
{
	for (uint32_t y = 0; y < fb.h; y++) {
		wdt_pet();
		for (uint32_t x = 0; x < fb.w; x++)
			px(x, y, g);
	}
}

static void glyph(uint32_t x0, uint32_t y0, char ch, uint32_t scale, uint8_t fg, uint8_t bg)
{
	if (ch < 0x20 || ch > 0x7e)
		ch = '?';
	const unsigned char *g = font8x16[ch - 0x20];
	if (x0 + 8 * scale > fb.w || y0 + 16 * scale > fb.h)
		return;
	for (uint32_t gy = 0; gy < 16; gy++)
		for (uint32_t gx = 0; gx < 8; gx++) {
			uint8_t c = (g[gy] & (0x80 >> gx)) ? fg : bg;
			for (uint32_t sy = 0; sy < scale; sy++)
				for (uint32_t sx = 0; sx < scale; sx++)
					px(x0 + gx * scale + sx, y0 + gy * scale + sy, c);
		}
}

#define TEXT_SCALE	2
#define MARGIN		24
#define BIG_SCALE	20

/* Background, the whole log, and the phase digit at the bottom right. */
static void draw(char digit, uint8_t bg)
{
	uint32_t cols = (fb.w - 2 * MARGIN) / (8 * TEXT_SCALE);
	uint32_t rows = (fb.h - 2 * MARGIN - 16 * BIG_SCALE) / (16 * TEXT_SCALE);
	uint32_t row = 0, col = 0;

	fill(bg);
	for (uint32_t i = 0; i < loglen && row < rows; i++) {
		if (logbuf[i] == '\n') {
			row++;
			col = 0;
			continue;
		}
		wdt_pet();
		if (col < cols)
			glyph(MARGIN + col * 8 * TEXT_SCALE, MARGIN + row * 16 * TEXT_SCALE,
			      logbuf[i], TEXT_SCALE, 0xff, bg);
		col++;
	}
	glyph(fb.w - MARGIN - 8 * BIG_SCALE, fb.h - MARGIN - 16 * BIG_SCALE,
	      digit, BIG_SCALE, 0xff, bg);
}

/* Live status: one text line just below the log and a big 2-digit counter. */
static void draw_status(uint32_t secs, uint32_t sts, uint32_t en, uint8_t bg)
{
	char line[40];
	static const char hex[] = "0123456789abcdef";
	uint32_t row = 1, n = 0;

	for (uint32_t i = 0; i < loglen; i++)
		row += logbuf[i] == '\n';
	for (const char *p = "T+"; *p; p++)
		line[n++] = *p;
	line[n++] = '0' + secs / 10 % 10;
	line[n++] = '0' + secs % 10;
	for (const char *p = "s sts="; *p; p++)
		line[n++] = *p;
	for (int i = 7; i >= 0; i--)
		line[n++] = hex[(sts >> (4 * i)) & 0xf];
	for (const char *p = " en="; *p; p++)
		line[n++] = *p;
	line[n++] = hex[en & 0xf];
	line[n++] = wdt_petting ? 'P' : '-';
	for (uint32_t i = 0; i < n; i++)
		glyph(MARGIN + i * 8 * TEXT_SCALE, MARGIN + row * 16 * TEXT_SCALE,
		      line[i], TEXT_SCALE, 0xff, bg);
	glyph(fb.w - MARGIN - 16 * BIG_SCALE, fb.h - MARGIN - 16 * BIG_SCALE,
	      '0' + secs / 10 % 10, BIG_SCALE, 0xff, bg);
	glyph(fb.w - MARGIN - 8 * BIG_SCALE, fb.h - MARGIN - 16 * BIG_SCALE,
	      '0' + secs % 10, BIG_SCALE, 0xff, bg);
}

/* ---- MDP probe ---- */

static uintptr_t sspp(int i)
{
	switch (i) {
	case 0: return MDSS_BASE + 0x5000;	/* vig0 */
	case 1: return MDSS_BASE + 0x7000;	/* vig1 */
	case 2: return MDSS_BASE + 0x25000;	/* dma0 */
	case 3: return MDSS_BASE + 0x27000;	/* dma1 */
	default: return MDSS_BASE + 0x29000;	/* dma2 */
	}
}

/* Register blocks watched for self-changing words: top, CTL0-3, PP0-3, INTF0-3. */
#define NR_REGION	13

static uintptr_t region(int i, uint32_t *words, const char **name)
{
	if (i == 0) {
		*words = 0x494 / 4;
		*name = "TOP";
		return MDP_TOP;
	}
	if (i <= 4) {
		*words = 0x1dc / 4;
		*name = "CTL";
		return CTL(i - 1);
	}
	if (i <= 8) {
		*words = 0xd4 / 4;
		*name = "PP";
		return PP(i - 5);
	}
	*words = 0x2c0 / 4;
	*name = "INTF";
	return INTF(i - 9);
}

static uint32_t snap[2][0x800];

static void snapshot(uint32_t *s)
{
	uint32_t n = 0, words;
	const char *name;

	for (int i = 0; i < NR_REGION; i++) {
		uintptr_t b = region(i, &words, &name);
		for (uint32_t w = 0; w < words && n < 0x800; w++)
			s[n++] = rd32(b + 4 * w);
	}
}

static void log_ticks(void)
{
	uint32_t n = 0, words, shown = 0;
	const char *name;

	for (int i = 0; i < NR_REGION; i++) {
		uintptr_t b = region(i, &words, &name);
		for (uint32_t w = 0; w < words && n < 0x800; w++, n++) {
			if (snap[0][n] == snap[1][n] || shown >= 16)
				continue;
			log_str("TICK ");
			log_str(name);
			log_hex(i == 0 ? 0 : (uint64_t)(i - 1) % 4, 1);
			log_ch('+');
			log_hex(4 * w, 3);
			log_kv("a", snap[0][n]);
			log_kv("b", snap[1][n]);
			log_nl();
			shown++;
		}
		(void)b;
	}
	if (!shown)
		log_str("TICK none in 100 ms\n");
}

static int fb_from_sspp(void)
{
	int active = -1;

	for (int i = 0; i < NR_SSPP; i++) {
		uintptr_t b = sspp(i);
		uint32_t size = rd32(b + SSPP_SRC_SIZE), addr = rd32(b + SSPP_SRC0_ADDR);
		uint32_t ystr = rd32(b + SSPP_SRC_YSTRIDE0), fmt = rd32(b + SSPP_SRC_FORMAT);

		log_str("SSPP");
		log_hex(i, 1);
		log_kv("size", size);
		log_kv("addr", addr);
		log_nl();
		log_str("     ");
		log_kv("ystr", ystr);
		log_kv("fmt", fmt);
		log_nl();
		log_str("     ");
		log_kv("unpk", rd32(b + SSPP_SRC_UNPACK));
		log_kv("op", rd32(b + SSPP_SRC_OP_MODE));
		log_nl();
		if (active < 0 && size && addr) {
			active = i;
			fb.base = addr;
			fb.w = size & 0xffff;
			fb.h = size >> 16;
			fb.stride = ystr & 0xffff;
			fb.bpp = ((fmt >> 9) & 3) + 1;
		}
	}
	return active;
}

/* Only draw inside cont_splash: an SSPP address may be an IOVA, and a stray
 * write into a TZ carve-out would fault. Elsewhere is logged, not drawn. */
static int fb_sane(void)
{
	return fb.base >= SPLASH_BASE &&
	       fb.base + (uint64_t)fb.stride * fb.h <= SPLASH_BASE + SPLASH_SIZE &&
	       fb.w >= 100 && fb.w <= 4096 &&
	       fb.h >= 100 && fb.h <= 4096 && fb.bpp >= 2 &&
	       fb.stride >= fb.w * fb.bpp && fb.stride <= 0x4000;
}

static int active_ctl(void)
{
	for (int i = 0; i < NR_CTL; i++) {
		uint32_t top = rd32(CTL(i) + CTL_TOP), intf = rd32(CTL(i) + CTL_INTF_ACTIVE);
		log_str("CTL");
		log_hex(i, 1);
		log_kv("top", top);
		log_kv("flush", rd32(CTL(i) + CTL_FLUSH));
		log_kv("intf", intf);
		log_nl();
	}
	for (int i = 0; i < NR_CTL; i++)
		if (rd32(CTL(i) + CTL_TOP) || rd32(CTL(i) + CTL_INTF_ACTIVE))
			return i;
	return 0;
}

static void log_wdt(const char *when)
{
	log_str("WDT ");
	log_str(when);
	log_kv("en", rd32(WDT_EN));
	log_kv("sts", rd32(WDT_STS));
	log_nl();
}

static void __attribute__((noreturn)) reset_to_android(void)
{
	wr32(IMEM_RESTART_REASON, RESTART_NORMAL);
	__asm__ volatile("dsb sy" ::: "memory");
	smc(PSCI_SYSTEM_RESET2, 0, 0, 0);	/* returns if not supported */
	smc(PSCI_SYSTEM_RESET, 0, 0, 0);
	wr32(PSHOLD, 0);
	for (;;)
		__asm__ volatile("wfe");
}

/* ---- entry points for start.S ---- */

static volatile int in_exc;

void exc_handler(uint64_t slot, uint64_t *regs)
{
	(void)regs;
	if (in_exc++)
		reset_to_android();
	log_str("\nEXCEPTION");
	log_kv("slot", slot);
	log_nl();
	log_kv("esr", rsr("esr_el1"));
	log_kv("far", rsr("far_el1"));
	log_nl();
	log_kv("elr", rsr("elr_el1"));
	log_nl();
	pstore_put(RAMOOPS_CONSOLE);
	pstore_put(ALT_RAMOOPS_CONSOLE);
	if (fb.base)
		draw('X', 0x00);
	delay_ms(30000);
	reset_to_android();
}

void secondary_main(uint64_t idx)
{
	(void)idx;
	smc(PSCI_CPU_OFF, 0, 0, 0);
}

void shim_main(uint64_t dtb)
{
	log_str("BRAMBLE probe 2: watchdog\n");
	log_wdt("entry");
	log_kv("bark", rd32(WDT_BARK_TIME));
	log_kv("bite", rd32(WDT_BITE_TIME));
	log_nl();
	wdt_pet();
	log_wdt("pet  ");
	log_kv("dtb", (uint32_t)dtb);
	log_kv("el", (uint32_t)(rsr("CurrentEL") >> 2));
	log_nl();
	log_kv("mdss_hw", rd32(MDSS_BASE));
	log_kv("mdp_hw", rd32(MDP_TOP));
	log_nl();

	int sp = fb_from_sspp();
	log_str("SCANOUT sspp");
	log_hex(sp < 0 ? 0xf : (uint64_t)sp, 1);
	if (sp < 0 || !fb_sane()) {
		log_str(" unusable, using cont_splash 1080x2340x4");
		fb.base = SPLASH_BASE;
		fb.w = PANEL_W;
		fb.h = PANEL_H;
		fb.bpp = 4;
		fb.stride = PANEL_W * 4;
	}
	log_nl();
	log_kv("fb", (uint32_t)fb.base);
	log_kv("w", fb.w);
	log_kv("h", fb.h);
	log_nl();
	log_kv("stride", fb.stride);
	log_kv("bpp", fb.bpp);
	log_nl();

	int ctl = active_ctl();
	log_str("CTL active ctl");
	log_hex(ctl, 1);
	log_nl();

	snapshot(snap[0]);
	delay_ms(100);
	snapshot(snap[1]);
	log_ticks();

	log_str("pet 0-6 s, then EN=0 and no pets until 60 s\n");
	pstore_put(RAMOOPS_CONSOLE);
	pstore_put(ALT_RAMOOPS_CONSOLE);
	draw(' ', 0x30);

	uint64_t f = rsr("cntfrq_el0"), t0 = now();
	for (uint32_t secs = 0, last = ~0U; secs < 60; secs = (now() - t0) / f) {
		if (secs >= 6 && wdt_petting) {
			wdt_petting = 0;
			wr32(WDT_EN, 0);
			__asm__ volatile("dsb sy" ::: "memory");
		}
		wdt_pet();
		if (secs != last) {
			draw_status(secs, rd32(WDT_STS), rd32(WDT_EN), 0x30);
			last = secs;
		}
	}
	log_wdt("60 s ");
	pstore_put(RAMOOPS_CONSOLE);
	pstore_put(ALT_RAMOOPS_CONSOLE);
	reset_to_android();
}
