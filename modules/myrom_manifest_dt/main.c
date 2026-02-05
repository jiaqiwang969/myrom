// MyROM v0.2: write a structured "measured boot" manifest into DeviceTree.
//
// Compared to v0.1 (boot-args only), this version:
// - Measures the in-memory (post-KPF) kernelcache Mach-O via SHA-256
// - Injects a JSON manifest into IODeviceTree:/chosen as `myrom-manifest`
// - (Best-effort) also exports a memory-map entry `MyROMManifest` pointing to a
//   persistent alloc_static() blob (for future kernel-side consumers).
//
// The DeviceTree property is the primary userland verification channel.

#include <pongo.h>
#include <mach-o/loader.h>
#include <stdbool.h>

#ifndef kCacheableView
#define kCacheableView 0x400000000ULL
#endif

#define MYROM_VERSION_STR "0.2"
#define MYROM_DT_PROP_KEY "myrom-manifest"
#define MYROM_MEMMAP_NAME "MyROMManifest"

static void (*g_prev_preboot_hook)(void);

extern struct mach_header_64* xnu_header(void);
extern uint64_t xnu_slide_value(struct mach_header_64* header);
// Not declared in pongoOS' public module header (example/include/pongo.h),
// but exported by pongoOS and safe for modules to use.
extern void* alloc_static(uint32_t size);
extern uint64_t vatophys_static(void* kva);

// Some checkra1n/pongoOS bundles export a smaller libc surface to modules.
// Keep this module self-contained by avoiding dependencies on strnlen/snprintf/etc.
static size_t my_strlen(const char* s)
{
    size_t n = 0;
    while (s && s[n]) n++;
    return n;
}

static size_t my_strnlen(const char* s, size_t maxlen)
{
    size_t n = 0;
    if (!s) return 0;
    while (n < maxlen && s[n]) n++;
    return n;
}

static void* my_memcpy(void* dst, const void* src, size_t n)
{
    uint8_t* d = (uint8_t*)dst;
    const uint8_t* s = (const uint8_t*)src;
    for (size_t i = 0; i < n; ++i) d[i] = s[i];
    return dst;
}

static void* my_memset(void* dst, int c, size_t n)
{
    uint8_t* d = (uint8_t*)dst;
    for (size_t i = 0; i < n; ++i) d[i] = (uint8_t)c;
    return dst;
}

// Best-effort per-boot nonce (we don't want to depend on pongoOS RNG helpers).
static inline uint64_t read_cntvct_el0(void)
{
    uint64_t v;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(v));
    return v;
}

// ---- Minimal SHA-256 implementation (public domain) ----

typedef struct
{
    uint8_t data[64];
    uint32_t datalen;
    uint64_t bitlen;
    uint32_t state[8];
} sha256_ctx_t;

static uint32_t rotr32(uint32_t x, uint32_t n) { return (x >> n) | (x << (32 - n)); }

static uint32_t ch(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (~x & z); }
static uint32_t maj(uint32_t x, uint32_t y, uint32_t z) { return (x & y) ^ (x & z) ^ (y & z); }
static uint32_t e0(uint32_t x) { return rotr32(x, 2) ^ rotr32(x, 13) ^ rotr32(x, 22); }
static uint32_t e1(uint32_t x) { return rotr32(x, 6) ^ rotr32(x, 11) ^ rotr32(x, 25); }
static uint32_t s0(uint32_t x) { return rotr32(x, 7) ^ rotr32(x, 18) ^ (x >> 3); }
static uint32_t s1(uint32_t x) { return rotr32(x, 17) ^ rotr32(x, 19) ^ (x >> 10); }

static const uint32_t k256[64] = {
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
    0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
    0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
    0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
};

static void sha256_transform(sha256_ctx_t* ctx, const uint8_t data[64])
{
    uint32_t a, b, c, d, e, f, g, h, t1, t2;
    uint32_t m[64];

    for (uint32_t i = 0, j = 0; i < 16; ++i, j += 4) {
        m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j + 1] << 16) | ((uint32_t)data[j + 2] << 8) | (uint32_t)data[j + 3];
    }
    for (uint32_t i = 16; i < 64; ++i) {
        m[i] = s1(m[i - 2]) + m[i - 7] + s0(m[i - 15]) + m[i - 16];
    }

    a = ctx->state[0];
    b = ctx->state[1];
    c = ctx->state[2];
    d = ctx->state[3];
    e = ctx->state[4];
    f = ctx->state[5];
    g = ctx->state[6];
    h = ctx->state[7];

    for (uint32_t i = 0; i < 64; ++i) {
        t1 = h + e1(e) + ch(e, f, g) + k256[i] + m[i];
        t2 = e0(a) + maj(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

static void sha256_init(sha256_ctx_t* ctx)
{
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667U;
    ctx->state[1] = 0xbb67ae85U;
    ctx->state[2] = 0x3c6ef372U;
    ctx->state[3] = 0xa54ff53aU;
    ctx->state[4] = 0x510e527fU;
    ctx->state[5] = 0x9b05688cU;
    ctx->state[6] = 0x1f83d9abU;
    ctx->state[7] = 0x5be0cd19U;
}

static void sha256_update(sha256_ctx_t* ctx, const uint8_t* data, size_t len)
{
    for (size_t i = 0; i < len; ++i) {
        ctx->data[ctx->datalen++] = data[i];
        if (ctx->datalen == 64) {
            sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void sha256_final(sha256_ctx_t* ctx, uint8_t hash[32])
{
    uint32_t i = ctx->datalen;

    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        sha256_transform(ctx, ctx->data);
        my_memset(ctx->data, 0, 56);
    }

    ctx->bitlen += (uint64_t)ctx->datalen * 8ULL;
    ctx->data[63] = (uint8_t)(ctx->bitlen);
    ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
    ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
    ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
    ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
    ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
    ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
    ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
    sha256_transform(ctx, ctx->data);

    for (i = 0; i < 4; ++i) {
        hash[i] = (uint8_t)((ctx->state[0] >> (24 - i * 8)) & 0xff);
        hash[i + 4] = (uint8_t)((ctx->state[1] >> (24 - i * 8)) & 0xff);
        hash[i + 8] = (uint8_t)((ctx->state[2] >> (24 - i * 8)) & 0xff);
        hash[i + 12] = (uint8_t)((ctx->state[3] >> (24 - i * 8)) & 0xff);
        hash[i + 16] = (uint8_t)((ctx->state[4] >> (24 - i * 8)) & 0xff);
        hash[i + 20] = (uint8_t)((ctx->state[5] >> (24 - i * 8)) & 0xff);
        hash[i + 24] = (uint8_t)((ctx->state[6] >> (24 - i * 8)) & 0xff);
        hash[i + 28] = (uint8_t)((ctx->state[7] >> (24 - i * 8)) & 0xff);
    }
}

// ---- helpers ----

static void hex_encode(char* out, size_t outsz, const uint8_t* in, size_t insz)
{
    static const char* hexd = "0123456789abcdef";
    if (outsz == 0) return;
    size_t need = insz * 2 + 1;
    if (outsz < need) insz = (outsz - 1) / 2;
    for (size_t i = 0; i < insz; ++i) {
        out[i * 2] = hexd[(in[i] >> 4) & 0xf];
        out[i * 2 + 1] = hexd[in[i] & 0xf];
    }
    out[insz * 2] = '\0';
}

static bool bootargs_append(const char* add, size_t limit)
{
    // gBootArgs points to the 0x8000_0000_00 "device" view; convert to cacheable view for string ops.
    char* cmdline = (char*)((uint64_t)gBootArgs->iOS13.CommandLine - 0x800000000ULL + kCacheableView);
    size_t cur = my_strnlen(cmdline, limit);
    if (cur == 0 && add[0] == ' ') add++; // avoid leading whitespace if CommandLine is empty
    size_t addlen = my_strlen(add);
    if (cur >= limit) return false;
    if (addlen >= (limit - cur)) return false;
    my_memcpy(cmdline + cur, add, addlen);
    cmdline[cur + addlen] = '\0';
    return true;
}

static bool buf_append(char** p, size_t* rem, const char* s)
{
    size_t n = my_strlen(s);
    if (*rem == 0) return false;
    if (n >= *rem) return false;
    my_memcpy(*p, s, n);
    *p += n;
    *rem -= n;
    **p = '\0';
    return true;
}

static void u32_hex8(char out[9], uint32_t v)
{
    static const char* hexd = "0123456789abcdef";
    for (int i = 7; i >= 0; --i) {
        out[i] = hexd[v & 0xf];
        v >>= 4;
    }
    out[8] = '\0';
}

static void u64_hex_min(char* out, size_t outsz, uint64_t v)
{
    static const char* hexd = "0123456789abcdef";
    if (outsz == 0) return;
    if (v == 0) {
        out[0] = '0';
        if (outsz > 1) out[1] = '\0';
        return;
    }
    char tmp[16];
    size_t n = 0;
    while (v && n < sizeof(tmp)) {
        tmp[n++] = hexd[v & 0xf];
        v >>= 4;
    }
    size_t w = (n + 1 <= outsz) ? n : (outsz - 1);
    for (size_t i = 0; i < w; ++i) {
        out[i] = tmp[n - 1 - i];
    }
    out[w] = '\0';
}

static bool build_manifest_json(char* out, size_t outsz, uint32_t nonce, const char* ksha256_hex, uint64_t slide, uint64_t klen)
{
    char nonce_hex[9];
    u32_hex8(nonce_hex, nonce);

    char slide_hex[17];
    u64_hex_min(slide_hex, sizeof(slide_hex), slide);

    char klen_hex[17];
    u64_hex_min(klen_hex, sizeof(klen_hex), klen);

    char* p = out;
    size_t rem = outsz;
    if (!buf_append(&p, &rem, "{\"myrom\":1,\"v\":\"" MYROM_VERSION_STR "\",\"nonce\":\"")) return false;
    if (!buf_append(&p, &rem, nonce_hex)) return false;
    if (!buf_append(&p, &rem, "\",\"ksha256\":\"")) return false;
    if (!buf_append(&p, &rem, ksha256_hex)) return false;
    if (!buf_append(&p, &rem, "\",\"slide\":\"0x")) return false;
    if (!buf_append(&p, &rem, slide_hex)) return false;
    if (!buf_append(&p, &rem, "\",\"klen\":\"0x")) return false;
    if (!buf_append(&p, &rem, klen_hex)) return false;
    if (!buf_append(&p, &rem, "\"}")) return false;
    return true;
}

static uint64_t kernelcache_file_size(struct mach_header_64* hdr)
{
    if (!hdr || hdr->magic != MH_MAGIC_64) return 0;
    uint64_t max_end = 0;
    struct load_command* lc = (struct load_command*)(hdr + 1);
    for (uint32_t i = 0; i < hdr->ncmds; ++i) {
        if (lc->cmdsize < sizeof(struct load_command)) return 0;
        if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
            struct segment_command_64* sg = (struct segment_command_64*)lc;
            uint64_t end = (uint64_t)sg->fileoff + (uint64_t)sg->filesize;
            if (end > max_end) max_end = end;
        }
        lc = (struct load_command*)((uint8_t*)lc + lc->cmdsize);
    }
    if (max_end == 0 || max_end > (128ULL * 1024ULL * 1024ULL)) return 0;
    return max_end;
}

// ---- DeviceTree injection (Apple DT, not libfdt) ----

static uint32_t align4_u32(uint32_t x) { return (x + 3U) & ~3U; }

static uint32_t dt_prop_entry_size(const dt_prop_t* prop)
{
    uint32_t l = prop->len & 0xffffffU;
    return (uint32_t)sizeof(dt_prop_t) + align4_u32(l);
}

static uint32_t dt_calc_node_size(const dt_node_t* node)
{
    uint32_t off = (uint32_t)sizeof(dt_node_t);
    for (uint32_t i = 0; i < node->nprop; ++i) {
        const dt_prop_t* prop = (const dt_prop_t*)((const uint8_t*)node + off);
        off += dt_prop_entry_size(prop);
    }
    for (uint32_t i = 0; i < node->nchld; ++i) {
        const dt_node_t* child = (const dt_node_t*)((const uint8_t*)node + off);
        off += dt_calc_node_size(child);
    }
    return off;
}

static uint32_t dt_copy_node_with_insert(const dt_node_t* in_node,
                                         uint8_t* out,
                                         uint32_t out_cap,
                                         const dt_node_t* insert_node,
                                         const char* insert_key,
                                         const void* insert_val,
                                         uint32_t insert_len)
{
    if (out_cap < sizeof(dt_node_t)) return 0;

    dt_node_t* out_node = (dt_node_t*)out;
    out_node->nprop = in_node->nprop + ((in_node == insert_node) ? 1U : 0U);
    out_node->nchld = in_node->nchld;

    uint32_t off_in = (uint32_t)sizeof(dt_node_t);
    uint32_t off_out = (uint32_t)sizeof(dt_node_t);

    for (uint32_t i = 0; i < in_node->nprop; ++i) {
        const dt_prop_t* prop_in = (const dt_prop_t*)((const uint8_t*)in_node + off_in);
        uint32_t ps = dt_prop_entry_size(prop_in);
        if (off_out + ps > out_cap) return 0;
        my_memcpy(out + off_out, prop_in, ps);
        off_in += ps;
        off_out += ps;
    }

    if (in_node == insert_node) {
        uint32_t vpad = align4_u32(insert_len);
        uint32_t ps = (uint32_t)sizeof(dt_prop_t) + vpad;
        if (off_out + ps > out_cap) return 0;

        dt_prop_t* prop_out = (dt_prop_t*)(out + off_out);
        my_memset(prop_out, 0, sizeof(dt_prop_t));
        // DT keys are fixed-size (DT_KEY_LEN) and must be NUL-terminated.
        size_t klen = my_strnlen(insert_key, DT_KEY_LEN - 1);
        my_memcpy(prop_out->key, insert_key, klen);
        prop_out->key[klen] = '\0';
        prop_out->len = insert_len;
        my_memset(prop_out->val, 0, vpad);
        my_memcpy(prop_out->val, insert_val, insert_len);

        off_out += ps;
    }

    for (uint32_t i = 0; i < in_node->nchld; ++i) {
        const dt_node_t* child_in = (const dt_node_t*)((const uint8_t*)in_node + off_in);
        uint32_t child_in_sz = dt_calc_node_size(child_in);

        uint32_t child_out_sz = dt_copy_node_with_insert(child_in,
                                                         out + off_out,
                                                         out_cap - off_out,
                                                         insert_node,
                                                         insert_key,
                                                         insert_val,
                                                         insert_len);
        if (child_out_sz == 0) return 0;
        off_in += child_in_sz;
        off_out += child_out_sz;
    }

    return off_out;
}

static bool dt_inject_chosen_manifest(const char* manifest, uint32_t manifest_len)
{
    uint32_t dt_len = gBootArgs->deviceTreeLength;
    uint32_t used = 0;
    if (dt_check(gDeviceTree, dt_len, &used) != 0) return false;

    dt_node_t* chosen = dt_find(gDeviceTree, "chosen");
    if (!chosen) return false;

    uint32_t add_sz = (uint32_t)sizeof(dt_prop_t) + align4_u32(manifest_len);
    uint32_t new_cap = used + add_sz;

    dt_node_t* new_dt = (dt_node_t*)alloc_static(new_cap);
    uint32_t written = dt_copy_node_with_insert(gDeviceTree,
                                                (uint8_t*)new_dt,
                                                new_cap,
                                                chosen,
                                                MYROM_DT_PROP_KEY,
                                                manifest,
                                                manifest_len);
    if (written == 0) return false;

    uint32_t check_used = 0;
    if (dt_check(new_dt, written, &check_used) != 0 || check_used != written) return false;

    // Update boot_args to point at the new DeviceTree blob.
    // gDeviceTree uses the cacheable view; boot_args->deviceTreeP is a "virt" pointer.
    uint64_t new_dt_p = (uint64_t)new_dt + gBootArgs->virtBase - gBootArgs->physBase + 0x800000000ULL - kCacheableView;
    gBootArgs->deviceTreeP = (void*)new_dt_p;
    gBootArgs->deviceTreeLength = written;
    gDeviceTree = new_dt;

    return true;
}

static void dt_export_memmap_manifest(void* blob, uint32_t blob_len)
{
    if (!blob || blob_len == 0) return;
    dt_node_t* memory_map = dt_find(gDeviceTree, "memory-map");
    if (!memory_map) return;
    struct memmap* map = dt_alloc_memmap(memory_map, MYROM_MEMMAP_NAME);
    if (!map) return;

    struct memmap mm;
    mm.addr = vatophys_static(blob);
    mm.size = blob_len;
    my_memcpy(map, &mm, sizeof(mm));
}

static void myrom_preboot_hook(void)
{
    // Run any existing hook first so we measure the final (patched) kernel image.
    if (g_prev_preboot_hook) {
        g_prev_preboot_hook();
    }

    struct mach_header_64* hdr = xnu_header();
    uint64_t klen = kernelcache_file_size(hdr);
    if (klen == 0) {
        bootargs_append(" myrom=1 myrom_v=" MYROM_VERSION_STR " myrom_err=kcsize", BOOT_LINE_LENGTH_iOS12);
        return;
    }

    uint8_t digest[32];
    sha256_ctx_t ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, (const uint8_t*)hdr, (size_t)klen);
    sha256_final(&ctx, digest);

    uint32_t nonce = (uint32_t)read_cntvct_el0();

    char ksha256_hex[65];
    hex_encode(ksha256_hex, sizeof(ksha256_hex), digest, sizeof(digest));

    uint64_t slide = xnu_slide_value(hdr);

    char json[256];
    if (!build_manifest_json(json, sizeof(json), nonce, ksha256_hex, slide, klen)) {
        bootargs_append(" myrom=1 myrom_v=" MYROM_VERSION_STR " myrom_err=jsonfmt", BOOT_LINE_LENGTH_iOS12);
        return;
    }

    uint32_t json_len = (uint32_t)(my_strlen(json) + 1); // include trailing NUL for ioreg-friendly display

    // Persist a copy in static memory and (best-effort) export it in /chosen/memory-map.
    void* blob = alloc_static(json_len);
    my_memcpy(blob, json, json_len);

    bool dt_ok = dt_inject_chosen_manifest(json, json_len);
    if (dt_ok) {
        dt_export_memmap_manifest(blob, json_len);
        bootargs_append(" myrom=1 myrom_v=" MYROM_VERSION_STR " myrom_dt=1", BOOT_LINE_LENGTH_iOS12);
    } else {
        // Fallback: keep a short record in boot-args so we can still verify something.
        bootargs_append(" myrom=1 myrom_v=" MYROM_VERSION_STR " myrom_dt=0 myrom_ksha256=", BOOT_LINE_LENGTH_iOS12);
        bootargs_append(ksha256_hex, BOOT_LINE_LENGTH_iOS12);
    }
}

void module_entry(void)
{
    g_prev_preboot_hook = preboot_hook;
    preboot_hook = myrom_preboot_hook;
}

char* module_name = "myrom_manifest_dt";

struct pongo_exports exported_symbols[] = {
    {.name = 0, .value = 0}
};
