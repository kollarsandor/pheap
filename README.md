# kissofdeath2 (pheap-runtime) – Teljes dokumentáció (Magyar)

> Forrás: https://deepwiki.com/kollarjade/kissofdeath2  
> Generálva: 2026-03-25

---

## Projektáttekintés

A `pheap-runtime` egy nagy teljesítményű, perzisztens memóriakezelő rendszer, amely tartós, tranzakciós és szemétgyűjtéssel támogatott tárolást biztosít összetett adatstruktúrák számára. Memória-leképezett fájlokat (mmap) alkalmaz, hogy a lemeztárolót perzisztens heapként kezelje, garantálva az adatok fennmaradását folyamatleállások és rendszer-újraindítások után, miközben pointer-szerű elérési sebességet biztosít.

A projekt három fő célt követ: tartósság (Write-Ahead Logging révén), biztonság (referencia-számlált szemétgyűjtés és hardver-alapú titkosítás), valamint teljesítmény (GPU-gyorsítás és architektúra-specifikus gyorsítótár-kezelés).

### Architekturális pillérek

A rendszer öt fő architekturális pillérre épül:

1. **Perzisztens Heap**: Fájl-háttérrel rendelkező memóriaterület, amely relatív címzést alkalmaz, hogy különböző memória-leképezési alapcímek esetén is érvényes maradjon.
2. **Tartóssági motor**: Egy Write-Ahead Log (WAL) és egy Recovery Engine, amelyek ARIES-stílusú helyreállítást implementálnak az atomicitás és konzisztencia biztosítása érdekében.
3. **Tranzakciós memória**: Egy `TransactionManager`, amely koordinálja a több objektumot érintő frissítéseket, lehetővé téve az atomikus `commit` vagy `rollback` műveleteket.
4. **Automatikus memóriakezelés**: Referencia-számlált szemétgyűjtő (GC), amely nyomon követi az objektumok élettartamát a perzisztens tárolóban.
5. **Hardver-gyökerű biztonság**: Integrált `SecurityManager`, amely AEAD titkosítást és TPM 2.0 integrációt biztosít kulcspecsételéshez.

### Rendszer-összefoglaló: alrendszerek

| Alrendszer | Fő kód-entitás | Felelősség |
|---|---|---|
| **Vezénylés** | `Runtime` | Életciklus-kezelés és alrendszer-összekötés |
| **Heap-kezelés** | `PersistentHeap` | mmap-kezelés és nyers I/O |
| **Foglalás** | `PersistentAllocator` | Szegregált szabad listák és méretosztály-kezelés |
| **Tartósság** | `WAL` & `RecoveryEngine` | Tranzakciós naplózás és összeomlás utáni helyreállítás |
| **Biztonság** | `SecurityManager` | AES-GCM titkosítás és TPM integráció |
| **Gyorsítás** | `GPUContext` | Futhark kernel dispatch és Unified Memory |

### Inicializálási sorrend

A `Runtime.init` függvény szigorú sorrendben inicializálja a komponenseket:

1. **Biztonsági inicializálás**: A `SecurityManager.init` kerül meghívásra először, hogy kezelje a mesterkulcsokat és titkosítási beállításokat.
2. **Heap & WAL leképezés**: A `PersistentHeap` és a `WAL` a megfelelő fájlokat memóriába képezi le.
3. **Helyreállítás**: A `RecoveryEngine` átvizsgálja a WAL-t, hogy visszajátssza a lezárt tranzakciókat, vagy visszavonjon részlegeseket – még mielőtt bármilyen új foglalás történne.
4. **Szolgáltatási réteg**: A `PersistentAllocator`, a `TransactionManager` és a `RefCountGC` a helyreállított heap tetején inicializálódik.
5. **Compute & API**: Végül a `GPUContext` és a `PersistentStore` (a magas szintű API) kerül előkészítésre.

---

## Kezdeti lépések és build rendszer

A projekt a **Zig Build System**-et alkalmazza, amelyet a `build.zig` fájl vezényel. A Zig képes zökkenőmentesen keresztfordítani és rendszerszintű C könyvtárakhoz linkelni.

### Rendszerfüggőségek

| Függőség | Cél | Linkelés |
|---|---|---|
| `libc` | Standard C könyvtár memóriakezeléshez és I/O-hoz | `exe.linkLibC()` |
| `libcrypto` | Kriptográfiai primitívek a `SecurityManager`-hez | `exe.linkSystemLibrary("crypto")` |
| `pthread` | Szálak és szinkronizáció (csak Linux) | `exe.linkSystemLibrary("pthread")` |
| `dl` | Dinamikus betöltés GPU kernelekhez (csak Linux) | `exe.linkSystemLibrary("dl")` |

### Konfigurációs opciók

- `-Dtarget=[arch-os-abi]`: Meghatározza a célplatformot (pl. `x86_64-linux-gnu`).
- `-Doptimize=[Mode]`: Beállítja az optimalizálási szintet (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`).

### Előállított binárisok

A build rendszer öt különálló binárist generál:

1. **pheap-runtime** – Az elsődleges futtatható fájl és a könyvtár belépési pontja. Integrálja az összes alrendszert, beleértve a WAL-t, a Transaction Managert és a GC-t. Forrás: `src/main.zig`.
2. **pheap-tool** – Parancssori segédprogram a heap vizsgálatához és diagnosztikájához. Lehetővé teszi a fejlesztőknek a `HeapHeader`, az objektumstatisztikák és a WAL-állapot vizsgálatát a teljes futtatókörnyezet nélkül. Forrás: `tools/inspect.zig`.
3. **pheap-repair** – Helyreállítási eszköz sérült heapek javítására. Képes újraépíteni a szabad listákat és ellenőrizni az ellenőrzőösszegeket, ha a `RecoveryEngine` automatikusan nem tudja feloldani az összeomlási állapotot. Forrás: `tools/repair.zig`.
4. **pheap-bench** – Teljesítménymérési csomag, amely méri a foglalási késleltetést, az írásamplifációt és a tranzakciós átviteli sebességet. Forrás: `src/benchmark.zig`.
5. **pheap-crash-test** – Speciális tesztelő bináris, amely a `CrashSimulator` segítségével hibákat injektál, és ellenőrzi a WAL és a heap atomicitását, tartósságát. Forrás: `test/crash_test.zig`.

### Futtatás és tesztelés

A runtime futtatásához és az egységtesztek végrehajtásához:

```bash
zig build run   # Build és futtatás
zig build test  # Egységtesztek futtatása
```

---

## Runtime vezénylés (Runtime & RuntimeConfig)

A `Runtime` struct a `pheap-runtime` rendszer central vezénylője. Kezeli az összes fő alrendszer életciklusát, inicializálását és koordinációját – beleértve a perzisztens heapet, a write-ahead naplózást, a tranzakciókezelést és a hardveres gyorsítást.

### RuntimeConfig mezők

| Mező | Típus | Leírás |
|---|---|---|
| `heap_path` | `[]const u8` | Fájlrendszerbeli útvonal a perzisztens heap tároló fájlhoz |
| `heap_size` | `u64` | A heap teljes mérete bájtban (ha 0, alapértelmezett 1 GB) |
| `wal_path` | `[]const u8` | Fájlrendszerbeli útvonal a Write-Ahead Log fájlhoz |
| `snapshot_dir` | `[]const u8` | Könyvtár, ahol a verziókövetett pillanatképek tárolódnak |
| `enable_encryption` | `bool` | AEAD titkosítás ki/bekapcsolása a `SecurityManager` révén |
| `master_key` | `?[]const u8` | Opcionális mesterkulcs a titkosításhoz |
| `enable_gpu` | `bool` | Futhark-alapú GPU számítási gyorsítás ki/bekapcsolása |
| `gpu_kernel_path` | `?[]const u8` | Útvonal a lefordított GPU kernel dinamikus könyvtárhoz |
| `gc_threshold` | `u64` | Memória-küszöbérték a szemétgyűjtés indításához |
| `snapshot_interval_ms` | `u64` | Automatikus pillanatkép-készítés gyakorisága |

### Nyilvános API felület

**Memóriakezelés:**
- `allocate(size, alignment)`: A `PersistentAllocator.alloc`-hoz delegál, `PersistentPtr`-t ad vissza.
- `free(ptr)`: A `PersistentAllocator.free`-hez delegál.

**Tranzakciókezelés:**
- `beginTransaction()`: Új tranzakciót indít a `TransactionManager` révén.
- `commit(tx)` / `rollback(tx)`: Véglegesíti vagy visszavon módosításokat.

**Gyökérkezelés:**
- `getRoot()` / `setRoot(tx, ptr)`: Kezeli a perzisztens objektumgráf belépési pontját.

**Karbantartás:**
- `runGC()`: Szinkron szemétgyűjtési ciklust indít.
- `flush()`: Biztosítja, hogy a `PersistentHeap` összes piszkos oldala szinkronizálva legyen a lemezre.

**Számítás:**
- `runGPUKernel(kernel_name, inputs, output_type)`: Futhark kernelt hajt végre, ha a `GPUContext` aktív.

### Deiniializálás

A `deinit` sorrend pontosan fordítottja az `init` sorrendnek, hogy a függőségek ne szabaduljanak fel, miközben magasabb szintű komponensek még szükségük van rájuk:

| Lépés | Komponens | Művelet |
|---|---|---|
| 1 | `GPUContext` | Dinamikus könyvtárak eltávolítása, GPU pufferek felszabadítása |
| 2 | `SnapshotManager` | Pillanatkép fájlleírók lezárása |
| 3 | `RefCountGC` | GC metaadatok és nyilvántartások tisztítása |
| 4 | `TransactionManager` | Aktív tranzakciók megszakítása, zárak felszabadítása |
| 5 | `PersistentAllocator` | Allocator metaadatok mentése a heapbe |
| 6 | `WAL` | Maradék rekordok kiöblítése, naplófájl lezárása |
| 7 | `PersistentHeap` | Memória-leképezés megszüntetése, heap fájl lezárása |
| 8 | `SecurityManager` | Érzékeny kulcsok törlése a memóriából |
| 9 | `ArenaAllocator` | A Runtime-hoz allokált összes host-oldali memória felszabadítása |

---

## Perzisztens Heap réteg

A **Perzisztens Heap Réteg** a `kissofdeath2` runtime alapvető tárolási absztrakcióját biztosítja. Egy standard fájlt tartós, címezhető memóriaterületté alakít a memória-leképezés (`mmap`) segítségével.

### Alapvető architektúra

A rendszer fájl-háttérrel rendelkező memóriamodellen működik, ahol a teljes heap leképezhető a folyamat virtuális cím-terére. Mivel a leképezés alapcíme futások között változhat, a heap réteg nyers mutatók helyett eltolás-alapú (offset-based) címzést és speciális mutató-absztrakciókat alkalmaz.

### Adatintegritás és tartósság mechanizmusai

- **Magic számok**: A `HEAP_MAGIC` (`"ZIGPHEAP"`) és az `OBJECT_MAGIC` (`0xDEADBEEF`) konstansok memória-régiók érvényesítésére szolgálnak átvizsgálás során.
- **CRC32c ellenőrzőösszegek**: Mind a `HeapHeader`, mind az `ObjectHeader` tartalmaz ellenőrzőösszegeket, amelyek `init`-kor vagy objektumeléréskor kerülnek ellenőrzésre.
- **Piszkos oldal nyomon követés**: A heap fenntart egy `dirty_pages` bithalmazt, amely nyomon követi, hogy a memória mely szegmensei szorulnak kiöblítésre a lemezre `msync` vagy speciális gyorsítótár-kiürítő utasítások révén.

---

## PersistentHeap: Memória-leképezett fájlkezelés

A `PersistentHeap` a `pheap-runtime` alapvető alrendszere, amely egy fizikai lemezfájllal háttérelt, nagy, összefüggő memóriablokkot kezel.

### Inicializálás és leképezés

Az `init` során a heap a következő műveletsort hajtja végre:

1. **Fájl beállítás**: Megnyitja vagy létrehozza a háttérfájlt, és gondoskodik a rendszer oldalméretéhez való igazításról.
2. **Memória leképezés**: Meghívja az `mmap`-ot `MAP.SHARED` és `PROT.READ | PROT.WRITE` jelzőkkel.
3. **Fejléc validáció**: Ha a fájl új, inicializálja a `HeapHeader`-t egyedi UUID-dal és magic bájtokkal. Ha létező fájlról van szó, ellenőrzi a fejléc integritását ellenőrzőösszegekkel.
4. **Nyomon követés beállítása**: Allokál egy `dirty_pages` logikai tömböt az oldal-granularitású módosítások követéséhez.

### HeapHeader elrendezés

| Mező | Leírás |
|---|---|
| `magic` | Magic bájtok (`ZIGPHEAP`) a fájlformátum azonosításához |
| `pool_uuid` | `u128` egyedi azonosító a heap példányhoz |
| `used_size` | A csak-hozzáfűzéses allokációs mutató aktuális eltolása |
| `dirty` | Jelző, hogy a heap tisztán lett-e lezárva |
| `root_ptr` | Mutató a perzisztens gráf gyökér-objektumára |

### Allokáció és mutató-feloldás

A `PersistentHeap` alapszintű, csak-hozzáfűzéses allokációs stratégiát valósít meg. Az `allocate` függvény:

1. Igazítja a kért méretet és az aktuális `used_size`-t.
2. Ellenőrzi, hogy nincs-e `OutOfMemory` a teljes `mmap` mérethez képest.
3. Frissíti a fejlécet, és `PersistentPtr`-t ad vissza, amely tartalmazza a heap `pool_uuid`-ját és a kiszámított `offset`-et.

Mivel az `mmap` alapcíme folyamat-újraindítások között változhat, nyers mutatók nem tárolhatók. A heap feloldó függvényeket biztosít: a `resolvePtr` egy `PersistentPtr`-t (UUID + eltolás) nyers `*anyopaque` mutatóvá alakít UUID és határok validálása után.

### Perzisztencia és piszkos oldal nyomon követés

Az írási műveletek `@memcpy`-t hajtanak végre a leképezett memóriára, majd meghívják a `markDirty` függvényt. A `flush` végigiterál a `dirty_pages` bithalmazon, és szinkronizálja az összes módosított oldalt a fájlba.

---

## Bináris sémák: HeapHeader, ObjectHeader és FreeBlock

Az `src/header.zig` fájlban definiált rögzített bináris struktúrák alkotják a perzisztens heap formátumának alapját.

### Alapkonstansok

| Konstans | Érték | Leírás |
|---|---|---|
| `HEAP_MAGIC` | `"ZIGPHEAP"` | 8 bájtos magic sztring a heap fájlhoz |
| `HEADER_SIZE` | `64` | Strukturális fejlécek minimális mérete |
| `CACHE_LINE_SIZE` | `64` | Standard igazítás perzisztens memória írásokhoz |
| `OBJECT_MAGIC` | `0xDEADBEEF` | Magic szám allokált objektumokhoz |
| `FREE_MAGIC` | `0xFEEDFACE` | Magic szám a szabad listán lévő blokkokhoz |

### HeapHeader

A `HeapHeader` minden perzisztens heap fájl első adatblokkja. Tartalmazza a teljes memóriakészlet metaadatait, beleértve az azonosítóját (UUID), a verziószámot, és mutatókat magas szintű struktúrákhoz.

| Mező | Típus | Leírás |
|---|---|---|
| `magic` | `[8]u8` | `ZIGPHEAP` értékre állítva |
| `version` | `u32` | Jelenlegi verzió (alapértelmezett: 1) |
| `flags` | `u32` | Bitmaszk; a 0. bit (`0x01`) a „piszkos" jelzőt jelzi |
| `pool_uuid` | `u128` | A heap készlet egyedi azonosítója |
| `endianness` | `Endianness` | Enum (`little=0x01234567`, `big=0x76543210`) |
| `checksum` | `u32` | A fejléc mezők CRC32c ellenőrzőösszege |
| `heap_size` | `u64` | A leképezett fájl teljes mérete |
| `root_offset` | `u64` | A gyökér-objektumra mutató fájl-eltolás |
| `transaction_id` | `u64` | Az utoljára sikeresen lezárt tranzakció azonosítója |
| `last_checkpoint` | `u64` | Az utolsó sikeres ellenőrzési pont WAL eltolása |

### ObjectHeader

Minden allokált objektumot megelőz egy `ObjectHeader`. Ez nyomon követi az objektum életciklusát, beleértve a referenciaszámlálót a szemétgyűjtéshez, a típusinformációt séma-azonosítón keresztül, és az állapotát.

**Objektum jelzők:**
- `FLAG_FREED (0x01)`: Az objektum már nem aktív, visszanyerésre jelölt.
- `FLAG_PINNED (0x02)`: Az objektum rögzített, nem mozgatható/gyűjthető.
- `FLAG_ARRAY (0x04)`: Jelzi, hogy az objektum összefüggő tömb, nem egyedi struct.

### FreeBlock

Amikor a memória nem tárol aktívan objektumot, `FreeBlock`-ként reprezentálódik. Ezek a blokkok kétszeresen láncolt listát alkotnak, amelyet a `PersistentAllocator` a szabad szegmensek nyomon követésére használ. A `next_offset` és `prev_offset` mezők a heap fájl elejéhez képest relatívak, lehetővé téve a lánc túlélését különböző memória-leképezési alapcímek esetén is.

### Integritás: CRC32c ellenőrzőösszegek

A kódbázis szoftveres CRC32c (Castagnoli) algoritmust implementál a bit-rothadás és részleges írások észlelésére. A `crc32cByte` függvény a `0x82F63B78` polinomot alkalmazza. Mind a `HeapHeader`, mind az `ObjectHeader` tartalmaz ellenőrzőösszegeket.

---

## PersistentAllocator: Szegregált szabad listák

A `PersistentAllocator` a `pheap-runtime` alapvető memóriakezelési komponense. Szegregált szabad lista stratégiát valósít meg a perzisztens memória kezeléséhez folyamat-újraindítások között.

### Allokátor architektúra

Az allokátor hibrid megközelítést alkalmaz: a kis objektumokat 32 szegregált méretosztályon keresztül kezeli, míg a nagy objektumokat (4096 bájtnál nagyobb) egy legjobb-illeszkedés stratégiával. Minden metaadat, beleértve a szabad lista mutatókat, magán a perzisztens heap fájlon belül tárolódik az azonnali összeomlás utáni helyreállítás lehetővé tételéhez.

### Méretosztály stratégia

- **MIN_BLOCK_SIZE**: 64 bájt
- **MAX_SMALL_SIZE**: 4096 bájt
- **Növekedési tényező**: Minden osztály körülbelül 1,25-szöröse az előzőnek, inicializáláskor kerül kiszámításra

### Foglalás életciklusa

Az `alloc(size, alignment)` meghívásakor:

1. **Zárolás**: Az allokátor megszerezte a `std.Thread.Mutex`-et.
2. **Tranzakció indítás**: Egy WAL tranzakció indul.
3. **Kis objektum út**: Ha `size <= 4096`, megkísérli az `allocateFromSizeClass`-t.
4. **Nagy objektum út**: Ha nagyobb, a `large_free_list`-et keresi.
5. **Heap bővítés**: Ha nem található szabad blokk, a heap végéről allokál az `allocateFromHeapEnd` révén.
6. **Metaadat frissítés**: Az `ObjectHeader` inicializálódik, a `total_allocated` növekszik, és egy `.allocate` rekord kerül hozzáfűzésre a WAL-hoz.

### Integritás és biztonság

Szálbiztonságot egy `std.Thread.Mutex` garantál, amely minden publikus műveletnél (`alloc`, `free`, `realloc`) megszerzésre kerül. Az allokátor a Zig standard könyvtárral való interfészt is biztosítja a `getAllocator()` révén.

---

## Mutató absztrakciók: PersistentPtr és RelativePtr

Perzisztens memóriarendszerben nyers virtuális memória mutatók nem tárolhatók közvetlenül a lemezen, mivel az `mmap` alapcíme folyamat-újraindítások között változhat. A `pheap-runtime` egy rétegzett mutató absztrakciós rendszert valósít meg, amely elválasztja az objektum fizikai helyét a logikai azonosságától.

### PersistentPtr: A logikai azonosság

A `PersistentPtr` egy 128 bites pool UUID-ból és egy 64 bites eltolásból áll, amely a pool elejétől számított pozíciót jelöli. Egy mutató érvényes, ha mind az `offset`, mind a `pool_uuid` nem nulla. Wyhash-t alkalmaz 64 bites hash-ek generálásához a `PointerTable`-ben való használathoz.

### RelativePtr(T): Az optimalizált tárolási formátum

A `RelativePtr(T)` egy bit-csomagolt mutató absztrakció, amelyet `extern struct` definíciókon belüli persistent objektumok hivatkozásához alkalmaznak. A `tagged` mező (u32) specifikus bitmaszkokat használ:

- **TAG_MASK (0x7FFF0000)**: 15 bites felhasználói tag tárolása.
- **INLINE_FLAG (0x80000000)**: Egyetlen bit, jelzi, hogy a mutató valójában inline érték.
- **Inline érték (0x00007FFF)**: Ha az `INLINE_FLAG` be van állítva, az alsó 15 bit egy nyers `u15` értéket tárol.

### RelativeSlice(T) és RelativeString

A `RelativeSlice(T)` kiterjeszti a relatív mutató koncepciót a perzisztens memóriában lévő változó hosszúságú tömbök támogatásához. Kombinálja a `RelativePtr(T)`-t egy 64 bites hosszal. A `RelativeString` egy kényelmi típus-alias `RelativeSlice(u8)`-ra.

### ResidentObjectTable és PointerTable

A folyamatos mutató-feloldás és UUID-validáció overhead elkerülése érdekében a futtatókörnyezet fenntart egy gyorsítótár-réteget a mutatókhoz, amelyek már leképeztésre kerültek az aktuális folyamat cím-terére. A `PointerTable` lineáris próbázást és Wyhash-t alkalmaz a hatékony keresés érdekében.

---

## Tartósság és összeomlás utáni helyreállítás

A **pheap** runtime a write-ahead naplózás (WAL), strukturált tranzakciókezelés és egy ARIES-stílusú recovery engine kombinációján keresztül biztosítja az adatok tartósságát és atomicitását. A tartóssági réteg a `PersistentHeap` és a magas szintű API között helyezkedik el, és minden módosítást rögzít a WAL-ban, mielőtt alkalmazná azokat a heap-en.

---

## Write-Ahead Log (WAL)

A WAL (Write-Ahead Log) a `kissofdeath2` tartóssági réteg kritikus komponense. Egy hozzáfűzéses, memória-leképezett naplót biztosít, amely minden strukturális és adatmódosítást rögzít a perzisztens heap alkalmazása előtt.

### WAL architektúra

A WAL egy rögzített méretű fejléccel és egymást követő változó hosszúságú rekordokkal rendelkező memória-leképezett fájlként implementált. A `head_offset` és `tail_offset` segítségével egy körkörös puffer-szerű kezelési rendszert valósít meg.

### WALHeader elrendezés

| Mező | Típus | Leírás |
|---|---|---|
| `magic` | `u32` | Magic szám `0xWALF1LE` |
| `version` | `u32` | WAL formátum verziója |
| `file_size` | `u64` | A WAL fájl aktuális mérete lemezen |
| `last_checkpoint` | `u64` | Az utolsó sikeres ellenőrzési pont eltolása |
| `transaction_counter` | `u64` | Monoton növekvő tranzakcióazonosító |
| `head_offset` | `u64` | A legrégebbi aktív rekord eltolása |
| `tail_offset` | `u64` | Eltolás, ahol a következő rekord kerül írásra |
| `checksum` | `u32` | A fejléc mezők CRC32c ellenőrzőösszege |

### Támogatott rekordtípusok

| Típus | Érték | Cél |
|---|---|---|
| `begin` | `1` | Új tranzakció-kontextus indítása |
| `commit` | `2` | Tranzakció sikeresen tartóssá tétele |
| `rollback` | `3` | Tranzakció megszakítása |
| `allocate` | `4` | Heap memória foglalás nyomon követése |
| `free` | `5` | Heap memória felszabadítás nyomon követése |
| `write` | `6` | Adatírás rögzítése egy specifikus heap eltoláshoz |
| `root_update` | `10` | Heap gyökérmutató módosításának rögzítése |
| `checkpoint` | `15` | Jelzi, hogy a napló az adott pontig csonkításra kerül |

### Memóriakezelés és szálbiztonság

A WAL `posix.mmap`-ot alkalmaz a naplófájl leképezéséhez. Az iniziális méret 64 MB; ha a `tail_offset` közelíti a fájl végét, az `expandFile` növeli a leképezést. Egy `lock: std.Thread.Mutex` védi a `tail_offset` módosításait.

### Ellenőrzési pont (Checkpointing)

Az ellenőrzési pont (`checkpoint`) lehetővé teszi a rendszernek a lemezterület visszanyerését. Amikor egy checkpoint következik be, a `head_offset` az aktuális `tail_offset`-re vagy a legrégebbi aktív tranzakció elejére kerül, és a `WALHeader` `last_checkpoint` mezője frissül.

---

## Transaction Manager

A `TransactionManager` koordinálja a **WAL**-t és a **PersistentHeap**-et az ACID tulajdonságok biztosításához.

### Tranzakció életciklus és állapotok

| Állapot | Leírás |
|---|---|
| `inactive` | A tranzakció inicializálva, de még nem indult el |
| `active` | A tranzakció jelenleg rögzíti a műveleteket |
| `prepared` | A tranzakció befejezte a műveleteket, készen áll a lezárásra |
| `committed` | A tranzakció sikeresen perzisztálta a változásait a WAL-ba és a heap-be |
| `rolled_back` | A tranzakció manuálisan megszakításra kerülete vagy meghiúsult |
| `failed` | Hiba történt a feldolgozás során, visszagörgetés szükséges |

### Konfliktusdetektálás és izoláció

A rendszer az izoláció megvalósításához nyomon követi a tranzakciók által elért memória-eltolásokat. A `hasConflict()` függvény két tranzakciót hasonlít össze, hogy meghatározza, interferálnak-e egymással. Konfliktus akkor áll fenn, ha az A tranzakció ír egy eltoláshoz, amelyet a B tranzakció olvas vagy szintén ír, ill. az A tranzakció olvas egy eltolást, amelyet a B tranzakció ír.

### Tranzakció timeout

A „zombie" tranzakciók megelőzése érdekében a `timeoutTransactions()` végigiterál az aktív tranzakciókon, összehasonlítja a `start_time`-ot az aktuális rendszeridővel, és visszagörgeti az előre meghatározott küszöböt meghaladó tranzakciókat.

---

## Recovery Engine

A Recovery Engine ARIES-stílusú háromfázisú helyreállítási algoritmust implementál. Gondoskodik arról, hogy rendszerösszeomlás vagy áramkimaradás után a heap konzisztens állapotba kerüljön.

### Helyreállítás fázisai

1. **Analízis fázis** (`runAnalysisPhase`): Feltérképezi a WAL-t az összes tranzakció állapotának azonosításához az utolsó ellenőrzési pont óta. Feltölti a `committed_transactions` és `incomplete_transactions` térképeket.
2. **Redo fázis** (`runRedoPhase`): Végigiterál a `committed_transactions`-ön. Minden tranzakcióhoz a `redoTransaction` feldolgozza a rekordokat: allokációk újra-ellenőrzése, adatírások újra-alkalmazása, allokátor-állapot visszaállítása, heap gyökér újra-mutatása.
3. **Undo fázis** (`runUndoPhase`): Feldolgozza az `incomplete_transactions`-t. A konzisztencia megőrzése érdekében az `undoTransaction` **fordított sorrendben** (legújabbtól a legrégebbiig) iterál a rekordokon.

### Visszagörgetési műveletek

| Művelet | Visszagörgetési akció |
|---|---|
| **Allocate** | A `freed` jelző beállítása az `ObjectHeader`-ben, ellenőrzőösszeg újraszámítása |
| **Write** | A memóriaterület visszaállítása előző állapotába (WAL undo adatai alapján) |
| **Free** | Az objektum visszaállítása a szabad listáról aktív állapotba |

### Véglegesítés

A fázisok befejezése után a `finalizeRecovery` elvégzi a tisztítást: törli a `dirty` jelzőt a `HeapHeader`-ben, WAL checkpoint indítása a felesleges naplók csonkításához, valamint a `verifyHeapConsistency()` meghívása a strukturális integritás ellenőrzéséhez.

---

## Gyorsítótár kiürítés és perzisztencia primitívek

A modern hardveren a tartósság garantálásához a pheap alacsony szintű CPU utasításokat alkalmaz, hogy megkerülje a volatilis CPU gyorsítótárakat.

### Architektúra-specifikus gyorsítótár kezelés

**x86_64 implementáció:**
- **CLWB (Cache Line Write Back)**: Az előnyben részesített utasítás. Visszaírja a módosított sort a memóriába anélkül, hogy szükségszerűen érvénytelenítené a gyorsítótárból.
- **CLFLUSHOPT (Cache Line Flush Optimized)**: Jobb átviteli sebességet biztosít a hagyományos `clflush`-hoz képest.
- **CLFLUSH**: A hagyományos sorosított kiürítő utasítás.

**AArch64 implementáció:**
- **DC CVAC**: Adatgyorsítótár tisztítása virtuális cím szerint a koherencia pontjáig.
- **DSB SY / ISB**: Adatszinkronizálási és utasítás-szinkronizálási barrier a gyorsítótár műveletek befejezésének biztosításához.

### Platformspecifikus tartóssági szinkronizáció (`persistent_sync`)

- **Linux**: `fdatasync(fd)` – adatok kiürítése metaadat frissítése nélkül.
- **macOS**: `fcntl(fd, F_FULLFSYNC)` – biztosítja, hogy az adatok a fizikai lemezre kerüljenek.
- **Windows**: `FlushFileBuffers(hFile)`.

### Flush batch rendszer (`flush_batch_t`)

A memória-barrierek teljesítmény-overhead minimalizálásához a rendszer egy batch rendszert biztosít: több memóriaterületet jelöl kiürítésre, egyetlen `sfence` végrehajtásával a batch végén.

---

## Memóriakezelés és szemétgyűjtés

A memóriakezelési alrendszer több rétegre épül: determinisztikus referenciaszámlálás az azonnali visszanyeréshez, nyomkövető szemétgyűjtő a ciklusos referenciák detektálásához, és pillanatkép-mechanizmus a pontos idejű helyreállításhoz és integritás-ellenőrzéshez.

### Referenciaszámlált & Particionált GC

Az elsődleges mechanizmus az objektumok visszanyeréséhez a `RefCountGC`. Az objektum életciklusát manuális és automatizált referencia-növelések és -csökkentések révén kezeli, amelyek WAL-által támogatottak.

- **Determinisztikus visszanyerés**: Az objektumok azonnali visszanyerésre kerülnek, ha `ref_count`-juk eléri a nullát.
- **Ciklus törés**: A körös referenciák kezelésére a rendszer egy `cycle_breaker` mechanizmust és egy nyomkövető `runCollection` menetet alkalmaz.
- **Particionált gyűjtés**: Nagy heap-eknél a `PartitionedGC` lehetővé teszi az 1 MB-os szegmensek inkrementális gyűjtését a késleltetési csúcsok minimalizálása érdekében.

### Snapshot Manager

A `SnapshotManager` lehetővé teszi a perzisztens heap teljes állapotának rögzítését egy adott időpontban.

- **Inkrementális pillanatképek**: A `DirtyPageTracker` és az `mprotect`-alapú SIGSEGV detektálás segítségével csak a legutolsó pillanatkép óta módosított oldalak kerülnek szerializálásra.
- **Integritás**: Minden pillanatkép tartalmaz egy `SnapshotHeader`-t Merkle gyökérrel, lehetővé téve a `verifySnapshot` számára az adatsérülés detektálását.
- **Visszaállítás**: A `restoreSnapshot` függvény képes verziókövetett `.snap` fájlokat visszajátszani a heap alapcímre.

### Magas szintű Perzisztens API (PersistentStore, Handle, Collections)

A `PersistentStore` és a hozzá tartozó típusok biztosítják a fejlesztők felé néző interfészt a perzisztens memóriával való interakcióhoz.

- **Handle-ek**: A `Handle(T)` típus egyetlen perzisztens objektum életciklusát kezeli, különböző `EditMode` állapotokat (olvasás, írás, kizárólagos) és automatikus tranzakció-integrációt biztosítva az `edit()` és `commit()` révén.
- **Kollekciók**: Beépített perzisztens kollekciókon, mint a `PersistentArray(T)` és `PersistentMap(K, V)`, a dinamikus növekedés és a belső mutatókezelés automatikusan történik.
- **Objektum életciklus**: Az API olyan segédprogramokat biztosít, mint a `createObject` és `setRoot`, amelyek a GC elérhetőség-elemzésének belépési pontjait hozzák létre.

---

## Biztonság és hardveres megbízhatóság

A **Security & Hardware Trust** alrendszer többrétegű védelmi architektúrát biztosít a perzisztens heap számára. Biztosítja az adatok bizalmasságát hitelesített titkosítással, az adatok integritását kriptográfiai hash-eléssel és Merkle fákkal, és hardver-háttérrel rendelkező bizalmi gyökeret TPM 2.0 segítségével.

### Biztonsági architektúra fő komponensei

- **Titkosítás**: AEAD (Authenticated Encryption with Associated Data) AES-GCM vagy ChaCha20-Poly1305 segítségével.
- **Kulcskezelés**: Hierarchikus kulcsstruktúra `master_key`-jel és régiónkénti, HKDF-SHA256 révén levezetett kulcsokkal.
- **Integritás**: Oldalankénti SHA-256 hash-elés és Merkle-fa ellenőrzés a jogosulatlan módosítások vagy „offline" manipulálás észlelésére.
- **Hardveres bizalmi gyökér**: TPM 2.0 integráció PCR-kötött adatpecsételéshez és monoton számlálókhoz a replay támadások megelőzésére.

### SecurityManager: Titkosítás és kulcskezelés

A `SecurityManager` kezeli a kriptográfiai anyagok életciklusát. Támogatja az `AES-GCM`-et hardveres gyorsítású környezetekben (futásidőben `hasAESNI()` révén detektálva) és a `ChaCha20-Poly1305`-öt szoftveres tartalékként. A nonce egyediség biztosítása érdekében atomikus `nonce_counter`-t tart fenn.

### TPM 2.0 integráció

A hardveres megbízhatóság egy C-alapú absztrakciós rétegen keresztül implementált, amely a Linux TSS2 stackkel interfészel. A `tpm2_context_t` kezeli az ESYS és TCTI kontextusokat a `/dev/tpm0`-val való kommunikációhoz. A Platform Configuration Registers (PCR-ek) biztosítják, hogy a szoftveres környezet nem lett kompromittálva, mielőtt az érzékeny adatok pecsétfelbontásra kerülnének.

### Biztonsági konfiguráció

| Funkció | Kód entitás | Alapértelmezett / Követelmény |
|---|---|---|
| **Mesterkulcs méret** | `AES_KEY_SIZE` | 32 bájt (256-bit) |
| **AEAD Nonce** | `AES_NONCE_SIZE` | 12 bájt |
| **Elsődleges kulcs handle** | `0x81000001` | Perzisztens TPM handle |
| **Hash algoritmus** | `TPM2_ALG_SHA256` | 0x000B |
| **Hardveres detektálás** | `hasAESNI()` | Futásidejű CPUID ellenőrzés |

---

## Séma Registry és típusrendszer

A Séma Registry futásidejű típusreflexiós rendszert biztosít a perzisztens heap számára. Lehetővé teszi a futtatókörnyezet számára a Zig kódban definiált `extern struct` típusok memória-elrendezésének megértését, elősegítve a biztonságos objektum-hozzáférést, az elrendezés ujjlenyomatozását és az adatmigráció kezelését sémaverziók között.

### SchemaRegistry

A `SchemaRegistry` fenntart egy leképezést egyedi séma-azonosítók és `SchemaEntry` struktúrák között, amelyek egy típus teljes elrendezési információját tartalmazzák. Szálbiztonság érdekében `std.Thread.RwLock`-ot alkalmaz.

### Típusreflexió és mezőmetaadatok

A rendszer a Zig típusokból részletes metaadatokat nyeri ki `comptime` reflexió segítségével.

| Struct | Mező | Leírás |
|---|---|---|
| `StructInfo` | `magic` | `SchemaMagic` (0xSCHEMA01) értéknek kell lennie |
| `StructInfo` | `checksum` | Az elrendezés ujjlenyomata |
| `FieldInfo` | `kind` | `FieldKind` enum (int, float, pointer, stb.) |
| `FieldInfo` | `offset` | Bájt-eltolás a struct elejétől |
| `FieldInfo` | `size` | A mező mérete bájtban |

### Objektummigráció és kompatibilitás

A registry adatstruktúrák fejlesztését támogatja egy migrációs rendszeren keresztül. Amikor egy objektum elavult `schema_id`-val kerül olvasásra a heap-ből, a `migrateObject` funkció az aktuális verzióra alakítja azt. Ha nincs explicit migrációs függvény regisztrálva, a rendszer automatikus mezőnkénti másolást kísérel meg azonos nevű és típusú mezőkre.

---

## Konkurencia primitívek

A `pheap-runtime` magas teljesítményű, perzisztens és hordozható szinkronizációs primitívek készletét biztosítja, amelyek kifejezetten a megosztott erőforrásokhoz való párhuzamos hozzáférésre terveztek. Ezek a primitívek 64 bájtos gyorsítótársorba illeszkednek, ami lehetővé teszi közvetlen beágyazásukat `extern struct` definíciókba.

### PMutex (Perzisztens Mutex)

A `PMutex` egy „pörgetés-majd-futex" zár. Spin-loop-on keresztül próbálja megszerezni a zárat rövid ideig tartott zárak esetén, és OS-szintű futex-ek segítségével vált kontextust magas versengés esetén.

- **Holtpont detektálás**: Ellenőrzi, hogy az aktuális szál már tartja-e a zárat, és `error.Deadlock`-ot ad vissza egyezés esetén.
- **Adaptív pörgetés**: A `spin_count` (alapértelmezett 100) meghatározza, hányszor hívja meg `std.Thread.spinLoopHint()`-et, mielőtt átadja a kernelnek.

### PRWLock (Perzisztens Olvasó-Írói Zár)

A `PRWLock` megosztott olvasási és kizárólagos írási hozzáférést biztosít. **Írói preferenciával** implementált az olvasás-intenzív munkaterheléseknél az írói éhezés megelőzése érdekében.

### PCondVar (Perzisztens Feltételi Változó)

A `PCondVar` komplex koordinációt tesz lehetővé, lehetővé téve a szálaknak specifikus predikátumok bevárását. **Generáció-alapú** számlálót implementál az „elveszett ébredés" probléma megelőzéséhez.

### RAII Guardok

A memória biztonság és a zár szivárgások megelőzése érdekében a modul RAII (Resource Acquisition Is Initialization) burkolókat biztosít:

- **LockGuard**: Kezeli a `*PMutex`-et.
- **ReadGuard**: Kezeli a `*PRWLock` megosztott oldalát.
- **WriteGuard**: Kezeli a `*PRWLock` kizárólagos oldalát.

---

## GPU és számítási gyorsítás

A GPU & Compute Acceleration réteg nagy teljesítményű, adat-párhuzamos feldolgozási képességeket biztosít a pheap-runtime-nak. Két fő komponensre osztható: egy Zig-alapú hardver-absztrakciós rétegre a kernel-kezeléshez és memória-dispatchhoz, valamint egy Futhark-alapú compute könyvtárra.

### GPUContext és Kernel Dispatch

A `GPUContext` a hardveres gyorsítás kezelésének central autoritása. Kezeli a kernel könyvtárak dinamikus betöltését és koordinálja az adat-párhuzamos feladatok végrehajtását.

- **Memóriakezelés**: Az adatokat `GPUArray(T)` struktúrák zárják körül, amelyek nyomon követik mind a host-oldali slice-okat, mind az eszköz-oldali mutatókat. Explicit adatmozgatást a `copyToDevice` és `copyFromDevice` biztosít.
- **Típusrendszer**: A `GPUValue` union és a `GPUValueType` enum típusbiztos interfészt biztosít skalárok és tömbök (int32, int64, float32, float64, bool) kernelekbe való átadásához.
- **Kernel életciklus**: A kerneleket a `registerKernel` regisztrálja, és a `runKernel` hajtja végre egy strukturált pipeline-ban: bemeneti típusok validálása, dispatch a betöltött dinamikus könyvtárba, eszköz-műveletek befejezésének szinkronizálása.

### Futhark Compute Könyvtár (compute.fut)

A `compute.fut` modul tartalmazza a tényleges adat-párhuzamos implementációkat GPU-végrehajtáshoz optimalizálva.

| Kategória | Fő primitívek |
|---|---|
| **Lineáris algebra** | `matrix_multiply`, `transpose`, `dot_product`, `vector_scale` |
| **Statisztika** | `mean_array`, `variance_array`, `std_dev_array`, `cosine_similarity` |
| **Gépi tanulás** | `softmax` (numerikusan stabil), `relu`, `sigmoid`, `leaky_relu`, `elu` |
| **Jelelfeldolgozás** | `convolve_1d`, `moving_average`, `exponential_moving_average` |
| **Tömb műveletek** | `sort_array`, `partition_array`, `histogram`, `scatter`/`gather` |

---

## Eszközök, diagnosztika és tesztelés

A `pheap-runtime` ökoszisztéma robusztus operációs és validációs eszközöket tartalmaz a perzisztens heap integritásának, teljesítményének és tartósságának biztosítása érdekében.

### Heap Inspector (pheap-tool)

A `HeapInspector` parancssori interfészt biztosít a heap fájl részletes vizsgálatához a teljes runtime indítása nélkül. Támogatott parancsok:

- **Fejléc validáció**: Ellenőrzi a `magic`, `version`, UUID és `checksum` integritást.
- **Foglalási statisztikák**: Kihasználtsági arányokat és méretosztály-eloszlást jelent az `AllocatorMetadata` beolvasásával.
- **Objektum átvizsgálás**: Lineáris heap-átvizsgálást végez `OBJECT_MAGIC` és `FREE_MAGIC` segítségével a szivárgó vagy sérült blokkok azonosítására.
- **WAL analízis**: Megvizsgálja a Write-Ahead Log head/tail eltolásait és tranzakció-számláló értékeit.

### Heap Repair Tool (pheap-repair)

A `HeapRepair` controller egy destruktív eszköz, amelyet tárolószintű sérülésből vagy logikai hibákból szenvedő heap-ek helyreállítására alkalmaznak. Négyfázisú pipeline-on keresztül működik: `repairHeader`, `repairAllocatorMetadata`, `repairFreeLists` és `repairObjects`. Képes javítani ellenőrzőösszeg-eltéréseket, a scratch-ből újraépíteni a sérült szabad listákat, és visszanyerni a nulla referenciaszámlálójú árva objektumok által foglalt helyet.

### Benchmarking Suite (pheap-bench)

A `BenchmarkSuite` szabványosított teljesítménymutatókat biztosít. Méri az átlagos, minimális és maximális késleltetést, másodpercenkénti műveleteket és MB/s átviteli sebességet.

- **Foglalási benchmarkok**: Méri a `PersistentAllocator.alloc` és `free` ciklusokat.
- **Tranzakciós benchmarkok**: Értékeli a `beginTransaction` és `commitTransaction` WAL rekordok overhead-ét.
- **Vegyes munkaterhelések**: Konfigurálható olvasás/írás arányokkal szimulál valódi forgalmi mintákat.

### Összeomlás-tesztelés és hibainjectálás (pheap-crash-test)

A `CrashSimulator` az elsődleges eszköz az ACID-ban lévő „Perzisztencia" ellenőrzésére. A `CrashInjector` segítségével szimulált folyamathibákat vált ki specifikus `CrashPhase` koordinátákon (pl. `before_wal_write`, `after_heap_write`). A csomag biztosítja, hogy szimulált összeomlás után a `RecoveryEngine` sikeresen visszajátssza a WAL-t és konzisztens állapotba hozza a heap-et, az objektum CRC32 ellenőrzőösszegeit egy `ExpectedObject` manifesttel összevetve ellenőrizve.

---

## Szójegyzék

### 1. Alapvető memóriakoncepcuk

**PersistentPtr** – Helyfüggetlen mutató a perzisztens heap-en belüli adatok hivatkozásához. Egy 128 bites `pool_uuid`-ból és egy 64 bites `offset`-ből áll a heap alapcímétől.

**RelativePtr(T)** – Bit-csomagolt mutató absztrakció `extern struct` definíciókon belüli perzisztens objektumok hivatkozásához. Inline értékeket is támogat kis adattípusokhoz.

**Méretosztály (Size Class)** – A `PersistentAllocator` 32 méretosztályból álló szegregált szabad-lista stratégiát alkalmaz. `MIN_BLOCK_SIZE`: 64 bájt, `MAX_SMALL_SIZE`: 4096 bájt, növekedési tényező ~1,25x.

### 2. Bináris elrendezés és magic konstansok

| Konstans | Érték | Leírás |
|---|---|---|
| `HEAP_MAGIC` | `"ZIGPHEAP"` | Azonosítja a perzisztens heap fájl elejét |
| `OBJECT_MAGIC` | `0xDEADBEEF` | Minden allokált objektum fejlécének előtagja |
| `FREE_MAGIC` | `0xFEEDFACE` | Azonosítja a szabad listán lévő blokkot |
| `ALLOCATOR_MAGIC` | `0xALL0CA7E` | A szegregált allokátor metaadat fejléce |
| `NODE_MAGIC` | `0xFREEL1ST` | Magic `FreeListNode` bejegyzésekhez |
| `WAL_MAGIC` | `0xWALF1LE` | Azonosítja a Write-Ahead Log fájlt |
| `SNAPSHOT_MAGIC` | `0xSNAPSHOT` | Inkrementális heap pillanatképek fejléce |
| `LOCK_MAGIC` | `0xL0CK0001` | Magic perzisztens szinkronizációs primitívekhez |

### 3. Tartósság és szinkronizáció

**ARIES-stílusú helyreállítás** – A `RecoveryEngine` háromfázisú helyreállítási folyamatot implementál: Analízis (WAL átvizsgálása), Redo (committed tranzakciók visszajátszása), Undo (uncommitted tranzakciók visszavonása).

**Gyorsítótár-kiürítő primitívek** – Függvények, amelyek biztosítják, hogy az adatok CPU volatilis gyorsítótárakból a perzisztencia doménbe kerüljenek. x86_64-en: `clwb`, `clflushopt`, `sfence`; AArch64-en: `dc cvac`, `dsb sy`, `isb`.

**Tranzakció életciklus** – A `TransactionManager` által kezelt, `RwLock`-ot alkalmazó izolációval és `WAL`-lal az atomicitáshoz. Állapotok: `inactive`, `active`, `prepared`, `committed`, `rolled_back`.

### 4. Biztonság és hardveres megbízhatóság

**TPM 2.0** – Hardver-háttérrel rendelkező biztonsági integráció. A rendszer TPM-et alkalmaz a titkosítási kulcsok specifikus platformállapotokhoz (PCR-ekhez) való „pecsételésére". A `tpm2_context_t` tárolja az ESYS és TCTI kontextusokat.

**AEAD titkosítás** – Authenticated Encryption with Associated Data. A `SecurityManager` AES-GCM-et vagy ChaCha20-Poly1305-öt alkalmaz a heap oldalak bizalmasságának és integritásának biztosítására.

### 5. Rendszer vezénylés

**Szemétgyűjtés (GC)** – A `RefCountGC` referenciaszámlálást alkalmaz azonnali visszanyeréshez, WAL-háttérrel a perzisztencia érdekében. A `cycle_breaker` mechanizmus kezeli azokat a köros referenciákat, amelyeket a referenciaszámlálás önállóan nem tud feloldani.

**GPU gyorsítás** – A Futhark egy adat-párhuzamos funkcionális nyelv, amelyet optimalizált C kerneleket generálására alkalmaznak, és amelyeket a `GPUContext` tölt be. Az Unified Memory lehetővé teszi, hogy a CPU és a GPU ugyanazt a virtuális cím-teret ossza meg, csökkentve az adatmozgatás overhead-ét.
