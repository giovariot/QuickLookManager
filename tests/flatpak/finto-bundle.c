/*
 * Costruisce un finto pacchetto .flatpak con GLib, cioè con l'implementazione
 * di riferimento di GVariant.
 *
 * Serve per provare il nostro lettore contro byte prodotti da chi il formato lo
 * definisce. Un test che costruisse il file con un serializzatore scritto da
 * noi non proverebbe niente: se avessimo capito male la specifica, lo stesso
 * errore starebbe da tutte e due le parti e il test passerebbe lo stesso.
 *
 * La forma è quella vera: il superblocco di un delta statico di OSTree, con in
 * testa il dizionario dei metadati aggiunto da Flatpak.
 *
 *   cc finto-bundle.c $(pkg-config --cflags --libs glib-2.0) -o finto-bundle
 *   ./finto-bundle fuori.flatpak icona.png
 */
#include <glib.h>
#include <string.h>

#define COMMIT_FORMAT "(a{sv}aya(say)sstayay)"
/* Per memoria, la forma intera del superblocco:
   "(a{sv}tayay" COMMIT_FORMAT "aya(uayttay)a(yaytt))" */

static GVariant *bytes_variant(const guchar *d, gsize n) {
    return g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, d, n, 1);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        g_printerr("uso: finto-bundle fuori.flatpak icona.png [zavorra in byte]\n");
        return 2;
    }
    /* La zavorra serve a far crescere il file oltre le soglie in cui GVariant
       cambia la misura degli scostamenti: un byte fino a 255, due fino a
       65.535, quattro oltre. Un lettore che sbaglia quella misura funziona sui
       file piccoli e si rompe su quelli veri, che sono tutti grandi. */
    gsize zavorra = argc > 3 ? (gsize) g_ascii_strtoull(argv[3], NULL, 10) : 0;

    gchar *png = NULL; gsize png_len = 0;
    if (!g_file_get_contents(argv[2], &png, &png_len, NULL)) {
        g_printerr("l'icona non si legge\n"); return 2;
    }

    GVariantBuilder mb;
    g_variant_builder_init(&mb, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&mb, "{sv}", "ref",
                          g_variant_new_string("app/org.gnome.Dictionary/x86_64/stable"));
    g_variant_builder_add(&mb, "{sv}", "origin",
                          g_variant_new_string("https://dl.flathub.org/repo/"));
    g_variant_builder_add(&mb, "{sv}", "runtime-repo",
                          g_variant_new_string("https://flathub.org/repo/flathub.flatpakrepo"));
    g_variant_builder_add(&mb, "{sv}", "metadata",
                          g_variant_new_string("[Application]\n"
                                               "name=org.gnome.Dictionary\n"
                                               "runtime=org.gnome.Platform/x86_64/45\n"
                                               "sdk=org.gnome.Sdk/x86_64/45\n"
                                               "command=gnome-dictionary\n"));
    g_variant_builder_add(&mb, "{sv}", "installed-size", g_variant_new_uint64(12345678));
    g_variant_builder_add(&mb, "{sv}", "icon-128", bytes_variant((const guchar *)png, png_len));
    GVariant *metadata = g_variant_builder_end(&mb);

    guchar csum[32];
    for (int i = 0; i < 32; i++) csum[i] = (guchar)i;

    /* Il commit: si costruisce coi figli gia' pronti invece che con la
       stringa di formato, perche' in `g_variant_new` un «ay» vuole un
       GVariantBuilder e non un GVariant, ed e' una trappola che costa
       un'oretta. */
    GVariant *cfigli[8];
    cfigli[0] = g_variant_new_array(G_VARIANT_TYPE("{sv}"), NULL, 0);
    cfigli[1] = bytes_variant(NULL, 0);
    cfigli[2] = g_variant_new_array(G_VARIANT_TYPE("(say)"), NULL, 0);
    cfigli[3] = g_variant_new_string("sottotitolo");
    cfigli[4] = g_variant_new_string("messaggio");
    cfigli[5] = g_variant_new_uint64(0);
    cfigli[6] = bytes_variant(csum, 32);
    cfigli[7] = bytes_variant(csum, 32);
    GVariant *commit = g_variant_new_tuple(cfigli, 8);

    /* La tupla del superblocco, coi figli gia' pronti. */
    GVariant *figli[8];
    figli[0] = metadata;
    figli[1] = g_variant_new_uint64(0);
    figli[2] = bytes_variant(NULL, 0);
    figli[3] = bytes_variant(csum, 32);
    figli[4] = commit;
    guchar *riempi = NULL;
    if (zavorra > 0) { riempi = g_malloc0(zavorra); }
    figli[5] = bytes_variant(riempi, zavorra);
    figli[6] = g_variant_new_array(G_VARIANT_TYPE("(uayttay)"), NULL, 0);
    figli[7] = g_variant_new_array(G_VARIANT_TYPE("(yaytt)"), NULL, 0);
    GVariant *fuori = g_variant_new_tuple(figli, 8);
    g_variant_ref_sink(fuori);

    GVariant *normale = g_variant_get_normal_form(fuori);
    const void *dati = g_variant_get_data(normale);
    gsize n = g_variant_get_size(normale);

    if (!g_file_set_contents(argv[1], (const gchar *)dati, n, NULL)) {
        g_printerr("non riesco a scrivere %s\n", argv[1]); return 2;
    }
    g_print("%s: %" G_GSIZE_FORMAT " byte, icona da %" G_GSIZE_FORMAT "\n", argv[1], n, png_len);
    return 0;
}
