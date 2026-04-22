pheap áttekintés

A pheap egy perzisztens kupactároló motor, amelyet arra terveztek, hogy ACID-kompatibilis, tranzakcionális memóriakezelést biztosítson olyan alkalmazások számára, amelyek tartós adatstruktúrákat igényelnek. Az in-memory allokáció teljesítményét egy lemezalapú tárolórendszer perzisztenciájával ötvözi, előreíró naplót és robusztus helyreállító motort használva az adatintegritás biztosítására összeomlások esetén.

A rendszer elsődlegesen Zig nyelven készült, és magas szintű API-t biztosít perzisztens objektumok, sémák és szemétgyűjtés kezelésére, miközben megőrzi az alacsony szintű vezérlést a memórialeképezés és a hardveresen gyorsított biztonság felett.

Alapvető célok

Tartósság: garantált perzisztencia előreíró napló és összeomlás utáni helyreállító mechanizmusok révén.

Tranzakcionális integritás: ACID tranzakciók összetett, többobjektumos frissítésekhez.

Memóriabiztonság: automatizált életciklus-kezelés referenciaszámlálás és jelöléses söpréses GC segítségével.

Rugalmasság: hardveres titkosítás, GPU-kiszervezés és inkrementális pillanatképek támogatása.

Rendszerarchitektúra

A pheap architektúrája több, szorosan összekapcsolt alrendszerből áll, amelyeket egy központi Runtime kezel. Az Orchestration réteget a Runtime képviseli, amely az életciklust, az inicializálást és az alrendszerek összekötését koordinálja. A Storage Engine réteg a PersistentHeap, amely az mmap régiókat, a fájl I O műveleteket és az oldalszintű perzisztenciát kezeli. A Memory Mgmt réteget a PersistentAllocator alkotja, amely blokkok allokálását, szabadlistákat és WAL-alapú frissítéseket kezel. A Durability réteget a WAL és a RecoveryEngine adja, amely a visszavonási újrajátszási naplót és az összeomlás utáni helyreállítási logikát biztosítja. A Concurrency réteget a TransactionManager valósítja meg, amely az izolációs szinteket és a tranzakciós állapotátmeneteket kezeli. Az Object Layer a PersistentStore, amely magas szintű API-t nyújt objektumfeloldáshoz és gyűjteménykezeléshez.

Kulcsfontosságú alrendszerek

1. Runtime és életciklus

A Runtime struktúra minden művelet belépési pontja. Burkolja a konfigurációt a RuntimeConfig segítségével, és kezeli az összes perzisztens komponens rendezett inicializálását és leállítását. Felső szintű API-t biztosít tranzakciók indításához, memóriafoglaláshoz és karbantartási feladatok, például pillanatképek vagy szemétgyűjtés indításához.

2. Build rendszer és eszközök

A projekt a Zig build rendszert használja négy elsődleges futtatható állomány előállítására.

pheap-runtime: a fő könyvtár és végrehajtási környezet.

pheap-tool: diagnosztikai segédprogram kupacfájlok és WAL-bejegyzések vizsgálatához.

pheap-repair: sérült kupacok helyreállítására szolgáló eszköz.

pheap-bench: teljesítménymérő csomag.

3. Tranzakcionális tárolás

A perzisztencia a PersistentHeap és a WAL együttesével valósul meg. A TransactionManager biztosítja, hogy minden művelet, beleértve a PersistentAllocator általi allokációkat is, visszagörgethető legyen hiba vagy explicit megszakítás esetén.

4. Objektum és sémakezelés

A PersistentStore típusbiztos burkolatot biztosít a nyers kupac fölött. SchemaRegistry-t használ az objektumelrendezések követésére, lehetővé téve például az automatikus migrációt és a reflexióalapú szemétgyűjtést. Az objektumokra PersistentPtr vagy RelativePtr segítségével hivatkozik, így a mutatók akkor is érvényesek maradnak, ha a kupac egy későbbi futás során más báziscímre kerül leképezésre.

Gyermekoldalak

Indulás és build rendszer: utasítások a Nix környezet beállításához, az OpenSSL függőség kezeléséhez és a Zig build rendszer használatához a különféle eszközlánc-komponensek lefordításához.

Futtatókörnyezet életciklusa és konfigurációja: technikai részletek a Runtime struktúráról, beleértve az inicializálási sorrendeket, a RuntimeConfig specifikációját és a tranzakcionális API felületet.

Indulás és build rendszer

Ez az oldal a pheap projekt build infrastruktúráját és környezetbeállítását részletezi. A pheap a Zig build rendszert használja több végrehajtható állományból álló architektúrájának, összetett modulfüggőségeinek és külső C könyvtárainak, például az OpenSSL-nek a kezelésére.

Build rendszer áttekintése

A pheap build rendszere a build.zig fájlban van definiálva. Arra tervezték, hogy négy különálló binárist állítson elő és egy erősen összekapcsolt Zig modulkészletet kezeljen. A build szkript automatizálja a modulok kereszt-összelinkelését, a C fejlécek include útvonalainak konfigurálását és a rendszerkönyvtárakhoz való linkelést.

A négy futtatható állomány

Bináris: pheap-runtime. Gyökérforrás: c/main.zig. Cél: az elsődleges démon futtatókörnyezet a perzisztens kupacműveletekhez.

Bináris: pheap-tool. Gyökérforrás: c/inspect.zig. Cél: diagnosztikai parancssori eszköz kupacfejlécek, WAL és objektummetaadatok vizsgálatához.

Bináris: pheap-repair. Gyökérforrás: c/repair.zig. Cél: helyreállító segédprogram sérült kupacfájlok javításához és szabadlisták újjáépítéséhez.

Bináris: pheap-bench. Gyökérforrás: src/benchmark.zig. Cél: teljesítménymérő csomag késleltetés és átviteli sebesség elemzéséhez.

Modulok kereszt-összelinkelése

A pheap build rendszer egyik sajátos eleme a registerModules függvény. Mivel a kódbázis magas szintű logikára a src könyvtárban és alacsony szintű tárolóprimitívekre a c könyvtárban oszlik, sok modul körkörös vagy összetett függőségekkel rendelkezik.

Ennek feloldására a build.zig egy kereszt-összelinkelést hajt végre, ahol minden modul importként regisztrálódik minden másik modul számára. Ez lehetővé teszi, hogy bármelyik fájl használhassa az @import függvényt bármely filename.zig fájlhoz, függetlenül annak könyvtárbeli helyétől.

A modulregisztráció folyamata

Először összegyűjti az összes fájlt az SRC_FILES és C_FILES listákból.

Ezután minden fájlhoz meghívja a b.createModule függvényt.

Utána végigiterál az összes modul listáján, és mindegyiken meghívja az addImport függvényt, létrehozva egy teljesen összekapcsolt függőségi gráfot.

Végül az összes modult a gyökér végrehajtható modulhoz csatolja.

Külső függőségek és környezet

OpenSSL integráció

A pheap kriptográfiai műveletekhez OpenSSL-re támaszkodik. A build rendszer kifejezetten az OpenSSL 3.4.1 verziót célozza.

A build.zig fájlban a linkOpenssl függvény a következőket kezeli.

A libcrypto könyvtár linkelése.

Konkrét Nix store útvonalak hozzáadása a fejlécekhez és könyvtárfájlokhoz.

A C könyvtár linkelésének engedélyezése a comp.linkLibC függvénnyel.

Nix környezet

A reprodukálható build érdekében a projekt Nix-et használ. A replit.nix fájl biztosítja, hogy az openssl csomag elérhető legyen a shell környezetben.

Replit munkafolyamat

A projekt tartalmaz egy .replit konfigurációt felhőalapú fejlesztéshez. A Project munkafolyamat automatizálja a build folyamatot.

Beállítja a PATH változót úgy, hogy tartalmazza a Zig fordítót.

Végrehajtja a zig build parancsot, és a kimenetet a /tmp/build.log fájlba irányítja.

Aktívan tartja a terminált hibakeresési célokra.

Build parancsok

A projekt fordításához és az egyes feladatok futtatásához a következő szabványos Zig parancsok használhatók.

zig build: mind a négy futtatható állományt lefordítja, és a zig-out/bin könyvtárba telepíti.

zig build run -- [args]: lefordítja és végrehajtja a pheap-runtime binárist.

zig build test: lefuttatja a c/main.zig fájlban definiált egységteszteket.

Megvalósítási részletek

Könyvtárlinkelés Linuxon

Linux célra fordításkor a build rendszer automatikusan linkeli a pthread és dl könyvtárakat a többszálúság és a dinamikus könyvtárbetöltés támogatására. Erre például a Futhark és GPU integráció miatt van szükség.

Include útvonalak

Minden futtatható állomány úgy van konfigurálva, hogy mind a c, mind az src könyvtárak include útvonalait tartalmazza. Ez lehetővé teszi, hogy a Zig kód könnyen hivatkozzon C fejlécekre, például cache_flush.h vagy tpm.c állományokra, ha erre @cImport segítségével szükség van.

Futtatókörnyezet életciklusa és konfigurációja

A Runtime struktúra a pheap rendszer központi vezénylője, amely burkolja az összes jelentős alrendszert és kezeli azok közös életciklusát. Egységes belépési pontot biztosít az inicializáláshoz, a tranzakcionális műveletekhez és a karbantartási feladatokhoz, például a szemétgyűjtéshez és a pillanatképkészítéshez.

Runtime konfiguráció

A RuntimeConfig struktúra határozza meg egy pheap példány működési paramétereit. Tartalmazza a perzisztenciához szükséges útvonalakat, a biztonsági beállításokat és a teljesítményküszöböket.

heap_path: a perzisztens kupacfájl elérési útja.

heap_size: a kupac kezdeti mérete, amely 0 esetén alapértelmezés szerint 1 GB.

wal_path: az előreíró napló fájljának elérési útja.

snapshot_dir: a pillanatképek tárolási könyvtára.

enable_encryption: jelző az átlátszó adattitkosítás engedélyezéséhez.

master_key: opcionális mesterkulcs a SecurityManager számára.

enable_gpu: jelző a GPU számítási integráció engedélyezéséhez.

gpu_kernel_path: a Futhark vagy OpenCL kernelkönyvtár elérési útja.

gc_threshold: referenciaszámlálásos GC indításának küszöbe.

snapshot_interval_ms: automatikus pillanatképek háttéridőköze.

Inicializálás és függőségek összekötése

A Runtime.init szigorú inicializálási sorrendet követ annak biztosítására, hogy a függőségek, például a biztonság és a WAL, elérhetők legyenek a további komponensek számára.

Első lépésként létrejön egy ArenaAllocator, amely a futtatókörnyezet-specifikus metaadatok életciklusát kezeli.

Másodikként inicializálódik a SecurityManager, hogy kezelni tudja a kupac és a WAL visszafejtését.

Harmadikként a PersistentHeap és a WAL inicializálódik a megadott útvonalakkal.

Negyedikként azonnal meghívódik a RecoveryEngine, hogy visszajátssza a függő tranzakciókat.

Ötödikként inicializálódik a PersistentAllocator, amely összekapcsolja a kupacot és a WAL-t.

Hatodikként a TransactionManager összekötődik a WAL-lal és a kupaccal, és regisztrálódik egy undoAllocationThunk, hogy az allokátor vissza tudja görgetni a sikertelen allokációkat.

Hetedikként inicializálódnak a további alrendszerek, például a GC, a SnapshotManager és az opcionális GPUContext.

Nyolcadikként létrejön a PersistentStore mint magas szintű felhasználói interfész.

Tranzakcionális API felület

A Runtime egyszerűsített API-t kínál a TransactionManagerrel és a PersistentAllocatorral való együttműködéshez. Biztosítja, hogy a tranzakciós környezetben végzett allokációk nyomon legyenek követve a lehetséges visszagörgetéshez.

beginTransaction: a TransactionManager.begin meghívásával új atomi munkafolyamatot indít.

allocate size alignment: memóriát foglal a PersistentAllocatoron keresztül. Ha aktív tranzakció van, automatikusan meghívja a trackAllocation függvényt a legutóbbi tranzakción, hogy sikertelenség esetén a memória felszabaduljon.

commit tx és rollback tx: a TransactionManager segítségével véglegesíti vagy visszavonja a változtatásokat.

setRoot tx ptr: tranzakciós környezetben frissíti a kupac gyökérmutatóját, biztosítva, hogy a perzisztens gráf belépési pontja atomi módon módosuljon.

Karbantartási műveletek

Szemétgyűjtés

A Runtime a RefCountGC-t indítja el az elérhetetlen perzisztens objektumok felszabadítására.

runGC: meghívja a gc.runCollection műveletet. Ez a folyamat a gyökérből kiindulva bejárja az objektumgráfot, és felszabadítja a zéró referenciaszámú objektumok memóriáját.

Pillanatképek és flush műveletek

createSnapshot: a SnapshotManager segítségével időpillanat-szerű kupacmásolatot hoz létre. Ezt tipikusan mentésekhez vagy helyreállítási pontként használják.

flush: kikényszeríti, hogy a PersistentHeap minden módosított oldala lemezre íródjon, és fsync-et hív az alatta lévő fájlleírón a tartósság garantálására.

Runtime statisztikák

A Runtime különböző alrendszerekből származó statisztikákat tud összesíteni RuntimeStats struktúrába, hogy pillanatképet adjon a rendszer állapotáról.

Kupachasználat: teljes méret és lefoglalt bájtok a PersistentAllocatorból.

WAL statisztikák: aktuális WAL méret és a checkpoint nélküli tranzakciók száma.

GC statisztikák: összegyűjtött objektumok száma és a visszanyert memória teljes mennyisége.

Alapvető tárolómotor

Az alapvető tárolómotor a pheap alaprétege, amely az adatok fizikai perzisztenciájáért, a memórialeképezett fájl kezeléséért és az alacsony szintű memóriaallokációért felel. Az nyers lemezbájtokat strukturált kupaccá alakítja, amely képes túlélni a rendszerösszeomlásokat, miközben magas teljesítményt tart fenn az mmap használatával.

A tárolómotor három elsődleges rétegből áll. A PersistentHeap a leképezést és a fájl I O műveleteket kezeli. A PersistentAllocator a blokkokat és a szabadlistákat kezeli. A Pointer System biztosítja a címtér-függetlenséget.

PersistentHeap: memórialeképezés és fájlelrendezés

A c/pheap.zig fájlban található PersistentHeap struktúra elsődleges interfészként szolgál egy memórialeképezett perzisztens tárolókészlet kezeléséhez. Kezeli a fájlleképezés életciklusát, fejlécellenőrzéssel és ellenőrzőösszegekkel biztosítja az adatintegritást, valamint megvalósítja a módosított oldalak követését, amelyet a pillanatkép- és helyreállító rendszerek használnak.

Memórialeképezés és életciklus

A PersistentHeap mmap segítségével vetíti a fájlt a folyamat virtuális címtartományába. Ez lehetővé teszi, hogy a rendszer a perzisztens tárolást nagy, összefüggő memóriablokkként kezelje, ami leegyszerűsíti a mutatóaritmetikát és az allokációt.

Inicializálási folyamat

Amikor a PersistentHeap.init meghívódik, a következő lépéseket hajtja végre.

Fájlbeállítás: megnyitja vagy létrehozza a file_path útvonalon lévő fájlt az openOrCreateFile segítségével, majd a kért aligned_size méretre vágja.

Leképezés: meghívja a mapFile függvényt, amely a posix.mmap köré épül PROT.READ, PROT.WRITE és MAP.SHARED beállításokkal.

Fejléc bootstrap: ha a fájl új, inicializál egy HeapHeader struktúrát, beállítja a dirty jelzőt, és lemezre flush-olja a fejlécet. Ha a fájl már létezik, meghívja a header.validate műveletet a magic bájtok, a verzió, az endianness és a CRC32c ellenőrzésére.

Állapotkövetés: lefoglal egy dirty_pages logikai tömböt annak követésére, hogy mely memórialapok módosultak.

Lezárás

A deinit függvény biztosítja, hogy minden függő változás flush-olódjon a lemezre a self.flush meghívásával, majd feloldja a memórialeképezést és bezárja a fájlleírót.

HeapHeader

A HeapHeader egy extern struct, amely a memórialeképezés legelején, azaz a 0 eltoláson helyezkedik el. Olyan kritikus metaadatokat tartalmaz, amelyek a készlet azonosításához és a konzisztencia fenntartásához szükségesek.

magic: konstans ZIGPHEAP.

version: a formátum verziója, jelenleg 1.

pool_uuid_low és pool_uuid_high: a kupackészlet 128 bites egyedi azonosítója.

checksum: a fejlécmezők CRC32c értéke, magát a checksum mezőt kivéve.

used_size: a lefoglalt terület aktuális csúcsértéke.

root_offset: az objektumgráf gyökerének eltolása.

flags: állapotbitmaszk, például a dirty jelzőt tartalmazó bit.

Módosított lapok követése és flush szemantika

A PersistentHeap szoftveres szintű dirty page követőt tart fenn az alatta lévő tárolóval való szinkronizálás optimalizálására.

Követési mechanizmus

Amikor a rendszer a write vagy writeObject segítségével adatot ír, a kupac meghívja a markDirty offset len függvényt. Ez kiszámolja, hogy mely virtuális memórialapokat érinti az írás, majd beállítja a megfelelő biteket a dirty_pages tömbben.

Flush és szinkronizálás

A rendszer különbséget tesz az egyes tartományok flush-olása és a teljes kupac szinkronizálása között.

flushRange offset len: msync-et vagy architektúrafüggő cache flush utasításokat, például CLWB-t használ adott memóriatartomány tartóssá tételéhez.

flush: végigiterál a dirty_pages bitkészleten és csak a módosított lapokat flush-olja lemezre, ami jelentősen csökkenti az I O terhelést nagy kupacoknál.

Gyökérmutató tárolása

A HeapHeader egy gyökérmutatót tárol, amely belépési pontként szolgál a teljes perzisztens objektumgráfhoz.

getRoot: lekéri a fejlécből a root_offset és root_uuid értékeket, majd visszaad egy PersistentPtr példányt.

setRoot tx ptr: új gyökéreltolással és UUID-vel frissíti a fejlécet, újraszámolja a checksumot, és flush-olja a fejlécet a tartósság biztosítására.

Tranzakcionális horgok

Bár a PersistentHeap alacsony szintű allocate és deallocate metódusokat biztosít, ezeket úgy tervezték, hogy beköthetők legyenek egy TransactionManager alá.

allocate tx size alignment: jelenleg egyszerű bump allokációt hajt végre a header.used_size növelésével. Teljes tranzakciós környezetben ezt a PersistentAllocator váltja fel.

tx paraméter: a setRoot és allocate metódusok tranzakciós argumentumot fogadnak, ami lehetővé teszi a tárolóréteg számára, hogy az előreíró naplózással integrálódjon az atomicitás biztosítása érdekében.

PersistentAllocator: blokkkezelés

A PersistentAllocator a PersistentHeap-en belüli memóriablokkok életciklusát kezeli. Hibrid allokációs stratégiát valósít meg, amely kis objektumokhoz elkülönített szabadlistákat, nagy objektumokhoz pedig best fit megközelítést alkalmaz, miközben minden állapotváltozást rögzít az előreíró naplóban a hibaálló konzisztencia érdekében.

Az allokátor közvetlenül a HeapHeader után helyezkedik el a memórialeképezett fájlban. Állapotát az AllocatorMetadata struktúra horgonyozza le, amely globális statisztikákat és a még ki nem osztott kupacterület határát követi.

AllocatorMetadata elrendezés

magic: konstans 0x414C4F43.

total_allocated: kumulatív lefoglalt bájtok.

total_freed: kumulatív felszabadított bájtok.

allocation_count: aktív allokációk teljes száma.

free_heap_offset: a kupac végén lévő összefüggő szabad terület kezdetének eltolása.

checksum: a metaadatblokk CRC32c integritásellenőrzése.

Allokációs stratégiák

Az allokátor kis és nagy allokációk között különböztet, hogy egyensúlyt tartson a töredezettség és a teljesítmény között.

Kis allokációk

A MAX_SMALL_SIZE értékig terjedő allokációk elkülönített szabadlistákat használnak.

32 méretosztály létezik.

A méretek 64 bájttól indulnak, és osztályonként nagyjából 1.25-szörösére nőnek.

Minden méretosztály egy duplán láncolt FreeListNode listát tart fenn.

Nagy allokációk

A MAX_SMALL_SIZE feletti allokációkat a large_free_list kezeli. Az allokátor best fit keresést végez a töredezettség minimalizálására. Ha a szabadlistában nem talál megfelelő blokkot, a kupacot az AllocatorMetadata free_heap_offset mezőjének növelésével bővíti.

Minden szabad blokk a lemezen FreeListNode fejlécet kap.

magic: 0x46524545.

mutatók: a prev és next mezők nyers mutatók helyett u64 eltolásokat használnak, hogy címtér-függetlenek maradjanak.

Tranzakcionális életciklus

Minden allokáció és felszabadítás WAL tranzakción belül történik annak biztosítására, hogy egy mutatófrissítés közbeni összeomlás ne szivárogtasson memóriát és ne hozzon létre kísértetobjektumokat.

Allokációs folyamat

Először megszerzi a self.lock mutexet a szálbiztonság érdekében.

Ezután a méretet a MIN_ALIGNMENT értékhez igazítja.

Utána új WAL tranzakciót indít.

Majd blokkot keres a méretosztályokban, vagy megnöveli a free_heap_offset értéket.

Frissíti a total_allocated és allocation_count mezőket.

Végül meghívja a heap.flushRange függvényt, hogy az új ObjectHeader és a frissített AllocatorMetadata tartósan rögzüljön.

Visszagörgetési mechanizmus

Az undoAllocation kritikus horog, amelyet a TransactionManager használ visszagörgetéskor. Ha egy memóriát foglaló tranzakció meghiúsul, ez a függvény felszabadítottként jelöli a blokkot és visszaállítja a metaadat-számlálókat.

Szálbiztonság és konkurencia

A PersistentAllocator egy durva szemcséjű std.Thread.Mutex segítségével biztosít szálbiztonságot. A zár az alloc, free, realloc és undoAllocation teljes hívásideje alatt fogva marad. Az allokátor saját tranzakciós életciklust kezel az alacsony szintű blokkkezeléshez, de az undoAllocation visszahíváson keresztül integrálódik a magasabb szintű TransactionManagerrel. Az AllocatorMetadata checksum mezőjét minden mezőmódosításkor újraszámolja a zár alatt.

Perzisztens mutatók és rezidens objektumtábla

A perzisztens mutatók alapmechanizmusként szolgálnak ahhoz, hogy a pheap címtér-függetlenséget érjen el. Mivel a perzisztens kupac különböző folyamatélettartamok vagy különböző gépek esetén eltérő báziscímekre képezhető le, a nyers virtuális memóriamutatók nem tárolhatók a lemezen. Ehelyett a pheap UUID-alapú készletazonosítást és relatív eltolásokat használ a memóriahelyek feloldására.

PersistentPtr és RelativePtr

A rendszer két elsődleges absztrakciót biztosít perzisztens adatok hivatkozására.

PersistentPtr: globálisan egyedi, stabil azonosító bármely objektumhoz bármely készletben. Egy 128 bites pool UUID-ből és a kupacbázistól mért 64 bites eltolásból áll.

RelativePtr T: egy perzisztens mutató memóriaoptimalizált változata, amelyet perzisztens struktúrákon belüli tárolásra terveztek. A UUID-t alacsony és magas 64 bites komponensekre bontja, és bittagelési képességeket tartalmaz.

Bittagelés és inline értékek

A RelativePtr egy 32 bites tagged mezőt használ metaadat tárolására a struktúraméret növelése nélkül.

Felhasználói tagek: egy 16 bites tag ágyazható be típusinformáció vagy állapot tárolására.

Inline értékek: ha az INLINE_FLAG be van állítva, a mutató nem memóriacímre hivatkozik, hanem egy 15 bites inline egészértéket hordoz. Ez kis optimalizációkhoz hasznos, amikor egy érték közvetlenül tárolható külön perzisztens objektum allokálása helyett.

Mutatófeloldási folyamat

Az adatok eléréséhez a RelativePtr-t fel kell oldani helyi virtuális címre. Ehhez a leképezett kupac aktuális báziscíme és a várt UUID szükséges a mutató integritásának biztosításához.

Relatív szeletek és karakterláncok

A RelativePtr-re építve a pheap definiálja a RelativeSlice T és RelativeString típusokat változó hosszúságú adatok perzisztens kezelésére.

A RelativeSlice T egy RelativePtr T és egy 64 bites hossz kombinációja.

A RelativeString a RelativeSlice u8 típus aliasa.

Egy szelet feloldásakor a rendszer először feloldja a mögöttes mutatót, majd a tárolt hossz alapján szabványos Zig szeletet épít.

Rezidens objektumtábla

A ResidentObjectTable és az azt megvalósító PointerTable gyorsítótárként és keresőmechanizmusként szolgál a memóriában rezidens objektumokhoz. A PersistentPtr kulcsokat illékony memóriacímekhez társítja.

A PointerTable nagy teljesítményű mutatókeresésre tervezett speciális hash map. A PersistentPtr UUID és offset értékén a Wyhash algoritmust használja hashkulcsok generálására. Nyílt címzést használ, beszúráskor és lekérdezéskor lineáris próbálgatással kezeli az ütközéseket, amíg egyezést vagy üres helyet nem talál.

Miközben a PersistentHeap a lemezen lévő nyers bájtokat kezeli, a ResidentObjectTable nyomon követi, hogy mely perzisztens objektumok lettek magas szintű Zig fogantyúkká példányosítva. Ez megakadályozza a redundáns feloldásokat, és biztosítja, hogy ugyanarra az eltolásra mutató több fogantyú szükség esetén ugyanazt az illékony állapotot ossza meg.

Mutatófordítási függvények

RelativePtr.init: nyers mutatóból és báziscímből relatív eltolást hoz létre.

RelativePtr.toPersistent: memóriaoptimalizált RelativePtr példányt globálisan egyedi PersistentPtr-re alakít.

RelativePtr.resolve: a relatív eltolást használható virtuális memóriamutatóvá alakítja vissza.

PointerTable.put: PersistentPtr kulcsot rezidens memóriacímmel társít.

PointerTable.get: visszaadja az adott PersistentPtr-hez tartozó rezidens memóriacímet.

Lemezformátum és fejlécstruktúrák

Ez az oldal a pheap tárolófájl bináris elrendezését részletezi. A formátumot memórialeképezett perzisztenciára tervezték, biztosítva, hogy az adatstruktúrák címtér-függetlenek és ellenőrzőösszegekkel hitelesíthetők legyenek. A kupac egy elsődleges globális fejlécből, majd a perzisztens allokátor által kezelt lefoglalt objektumok és szabad blokkok sorozatából áll.

Globális kupacelrendezés

A kupacfájl egy fix méretű HeapHeaderrel kezdődik, amelyet az adatrégió követ. A fájlon belüli minden eltolás a fájl elejéhez viszonyított, hogy a rendszer különböző memórialeképezések között is hordozható maradjon.

A HeapHeader a fájl első 256 bájtját foglalja el. Olyan kritikus metaadatokat tartalmaz, amelyek a készlet azonosításához, az integritás ellenőrzéséhez és az objektumgráf gyökerének megtalálásához szükségesek.

magic: konstans ZIGPHEAP.

version: formátumverzió, jelenleg 1.

flags: állapotbitmaszk, például a Dirty Flag a 0x01 értéken.

pool_uuid: a kupackészlet egyedi azonosítója.

endianness: 0x01234567 little endian, vagy 0x76543210 big endian.

checksum: a fejlécmezők CRC32c értéke.

heap_size: a leképezett fájl teljes mérete.

root_offset: a gyökérobjektum fájleltolása.

allocator_offset: az AllocatorMetadata eltolása.

Objektumok és szabad blokkok

A kupac adatterülete blokkokra van osztva. Minden blokk, akár lefoglalt, akár szabad, olyan fejléccel kezdődik, amely azonosítja a típusát és méretét.

Minden PersistentStore-on keresztül allokált perzisztens objektumot ObjectHeader előz meg. Ez a fejléc a GC és a sémareflexió számára szükséges metaadatokat követi.

magic: 0xDEADBEEF.

ref count: u32 mező a bejövő hivatkozások számával.

schema ID: az objektumot a SchemaRegistry egyik típusához kapcsolja.

flags: FLAG_FREED azt jelzi, hogy az objektum már nem aktív. FLAG_PINNED megakadályozza a begyűjtést. FLAG_ARRAY azt jelzi, hogy a hasznos teher összefüggő tömb.

FreeBlock

Amikor egy blokkot nem objektum foglal, FreeBlockként kezelik.

magic: 0x46524545, azaz FREE.

next: a következő szabad blokk u64 eltolása az allokátor szabadlistájában.

Integritás és ellenőrzőösszegezés

A hardverszintű sérülések vagy részleges írások észlelésére a pheap CRC32c integritási sémát használ.

A HeapHeader.computeChecksum a teljes 256 bájtos fejlécen számít CRC32c értéket, miközben a checksum mezőt a számítás közben nullázza.

A HeapHeader.validate a következőket ellenőrzi.

Magic egyezés: biztosítja, hogy a fájl valódi pheap fájl legyen.

Verziókompatibilitás: biztosítja, hogy a futtatókörnyezet képes legyen olvasni a fájlverziót.

Endianness: megakadályozza más architektúrán létrehozott kupac betöltését.

Checksum: igazolja, hogy a fejléc bitjei nem sérültek.

Dirty flag életciklus

A HeapHeader flags mezője egy Dirty Bitet tartalmaz 0x01 értékkel.

Beállítás: amikor a kupacot írásra megnyitják vagy tranzakció kezdődik.

Törlés: csak sikeres fsync vagy checkpoint után, amikor minden WAL rekord alkalmazásra került és a kupac konzisztens.

Helyreállítás: ha a Dirty Bit inicializáláskor beállítva marad, a RecoveryEngine WAL visszajátszást indít.

Tranzakciók és tartósság

A pheap tárolómotor a WAL, a TransactionManager és a RecoveryEngine összehangolt architektúráján keresztül biztosítja az ACID tulajdonságokat. A tartósságot az biztosítja, hogy a kupac módosításai előbb a WAL-ba kerülnek rögzítésre, és csak utána íródnak a perzisztens kupacfájlba. A TransactionManager vezénylőként működik, a WAL-t használja perzisztenciára, a RecoveryEngine-t pedig konzisztencia-visszaállításra indításkor.

Előreíró napló

A WAL a perzisztens változtatások igazságforrása. Memórialeképezett fájlként van kezelve, amely dinamikusan bővül. Globális fejlécből és tranzakciós rekordok egymás utáni folyamából áll.

WALHeader

magic: WAL_MAGIC, azaz 0x57414C46.

version: formátumverzió, jelenleg 1.

file_size: a WAL fájl teljes mérete a lemezen.

last_checkpoint: az utolsó sikeres checkpoint eltolása.

transaction_counter: monoton növekvő tranzakcióazonosító.

head_offset: az a hely, ahová a következő rekord íródik.

tail_offset: a napló legöregebb érvényes rekordja.

checksum: a fejlécmezők CRC32c értéke.

Rekordtípusok

begin: a tranzakció kezdete.

commit: sikeres befejezést jelez, a változások alkalmazhatók.

rollback: megszakított tranzakciót jelez.

allocate: kupacblokk-allokációs esemény.

free: kupacblokk-felszabadítási esemény.

write: kupacadat módosítása, beleértve a visszavonáshoz szükséges korábbi adatot.

root_update: a kupac gyökérmutatójának frissítése.

checkpoint: azt jelzi, hogy a napló szinkronizálódott a kupaccal.

Tranzakciós életciklus a WAL-ban

Begin: a beginTransaction növeli a transaction_counter értékét és inicializál egy Transaction struktúrát. Ekkor begin rekord íródik a naplóba.

Műveletek rögzítése: tranzakció közben különféle műveletek, például írás, allokáció és felszabadítás kerülnek naplózásra. Írás esetén a WAL undo adatot, azaz az eredeti memóriaállapotot tárolja a visszagörgetéshez.

Commit és rollback: commit esetén commit rekord kerül a naplóba, és amikor ez tartósan a lemezre kerül, a tranzakció tartósnak tekinthető. Hiba esetén rollback rekord íródik, és a RecoveryEngine a tárolt undo adatot használja a részleges változtatások visszavonására.

Checkpoint: a napló csonkolására szolgál. Biztosítja, hogy az adott eltolásig tartozó összes elkötelezett tranzakció teljesen megjelenjen a fő pheap fájlban, így a tail_offset előremozdulhat és hely szabadulhat fel.

Megvalósítási részletek

A WAL fájl alapmérettel indul, tipikusan 64 MB értékkel. Amikor a head_offset megközelíti a leképezett régió végét, a rendszer megnöveli az alatta fekvő fájlt, frissíti a memórialeképezést, majd a WALHeader.file_size mezőt is.

A getTransactions függvényt a helyreállítás és az eszközök, például a pheap-tool használják a napló állapotának újjáépítésére. A tail_offset és a head_offset között lineárisan bejárja a rekordokat, és a record_checksum segítségével ellenőrzi őket.

A WAL minden publikus metódusát std.Thread.Mutex védi, hogy a több szálból jövő írások ne keveredjenek össze, és a head_offset, valamint a sequence számláló konzisztens maradjon.

Tranzakciókezelő

A TransactionManager a pheap ACID műveleteinek központi koordinátora. Kezeli a tranzakciók életciklusát, nyomon követi az olvasási és írási halmazokat az ütközésérzékeléshez, és biztosítja, hogy a kupac minden módosítása tartósan bekerüljön a WAL-ba, mielőtt a perzisztens kupacon alkalmaznák.

Tranzakciós életciklus

A tranzakció a TransactionState enumerációban meghatározott több állapoton halad keresztül.

inactive: a tranzakció inicializálva van, de még nem indult el.

active: a tranzakció jelenleg elfogad műveleteket és követi a halmazokat.

prepared: a tranzakció előkészítve van commitra, többfázisú környezetekben használatos.

committed: a tranzakció sikeresen kiírta commit rekordját a WAL-ba.

rolled_back: a tranzakciót kézzel vagy automatikusan megszakították, a változtatások elvetődnek.

failed: a tranzakció hibába ütközött és nem folytatható.

Ütközésérzékelés

A TransactionManager optimista konkurenciakezelést valósít meg read_set és write_set követéssel.

Read set: a tranzakció során olvasott kupacmemória-eltolások.

Write set: a tranzakció során módosított kupacmemória-eltolások.

A hasConflict függvény két tranzakció halmazait hasonlítja össze. Ütközés akkor észlelhető, ha az aktuális tranzakció write_set elemei átfedik egy másik tranzakció read_set elemeit, ha az aktuális tranzakció write_set elemei átfedik egy másik tranzakció write_set elemeit, vagy ha az aktuális tranzakció read_set elemei átfedik egy másik tranzakció write_set elemeit.

Műveletek rögzítése

A TransactionManager magas szintű API-t biztosít különböző művelettípusok rögzítésére. Minden művelet a tranzakció operations listájába kerül, és párhuzamosan naplózódik a WAL-ba.

recordWrite: meglévő kupacadat módosítását rögzíti. Az undohoz old_data, a redohoz new_data kerül mentésre.

recordAllocate: új memóriaallokációt követ. A trackAllocation segítségével rögzíti az eltolást és a méretet.

recordFree: egy memóriablokk felszabadítását rögzíti.

recordRootUpdate: kifejezetten a kupac gyökérmutatójának változását követi.

Undo allokációs horog

A memóriaallokációk visszagörgetésének kezeléséhez a TransactionManager undo_allocation_fn horgot támogat. Ezt a setAllocatorHook segítségével lehet regisztrálni. Ha egy allokációt végző tranzakció visszagörgetődik, a menedzser meghívja ezt a horgot, hogy a memória visszakerüljön a PersistentAllocator szabadlistájába.

Konkurencia és időtúllépések

A TransactionManager std.Thread.RwLock segítségével védi belső active_transactions térképét. A zár a begin, commit és rollback műveletek során kerül megszerzésre. A tranzakciók start_time mezőt is tartalmaznak, így a menedzser felismerheti a túl régóta futó tranzakciókat, és automatikus visszagörgetést indíthat az erőforráskimerülés vagy holtpontok elkerülésére. A menedzser alapértelmezés szerint legfeljebb 1024 aktív tranzakciót enged.

Egy írási művelet adatfolyama

A felhasználó meghívja a recordWrite tx offset data függvényt.

A menedzser a megadott eltoláson beolvassa az old_data értéket a PersistentHeapből.

Létrehoz egy Operation objektumot old_data és new_data tartalommal, majd hozzáfűzi a tx.operations listához.

A változás ezután bekerül a WAL-hoz tartozó tranzakcióba.

Összeomlás utáni helyreállító motor

A RecoveryEngine feladata, hogy egy nem tiszta leállás vagy rendszerhiba után konzisztens állapotba hozza vissza a perzisztens kupacot. ARIES-stílusú helyreállítási protokollt használ, amely elemzési, újrajátszási és visszavonási fázisokból áll.

Helyreállítási életciklus

Amikor egy PersistentHeap megnyílik, a rendszer megvizsgálja a HeapHeader dirty jelzőjét. Ha ez be van állítva, vagy ha a WAL aktív tranzakciókat tartalmaz, a recover függvény meghívódik.

Elemzés

Az elemzési fázis átvizsgálja a WAL-t annak azonosítására, hogy a legutóbbi checkpoint óta mely tranzakciók elkötelezettek és melyek hiányosak.

Az elkötelezett tranzakciók a committed_transactions térképbe kerülnek a redo fázis számára.

A hiányos, aktív vagy előkészített tranzakciók az incomplete_transactions térképbe kerülnek, hogy az undo fázis visszagörgesse őket.

Az elemzés meghatározza a legutóbbi konzisztens állapotot is a helyreállítási munka határolására.

Redo

A redo fázis biztosítja, hogy minden elkötelezett tranzakció hatása megjelenjen a perzisztens kupacban.

A motor végigiterál az elkötelezett tranzakciókon és újraalkalmazza a WALRecord bejegyzéseket.

Allokációs redo: újra beállítja az ObjectHeader freed bitjét és frissíti az ellenőrzőösszegeket.

Írási redo: a heap.write segítségével ismét alkalmazza az adatfrissítéseket.

Metaadat redo: visszajátssza a kupacbővítéseket és a gyökérmutató-frissítéseket.

Undo

Az undo fázis visszagörgeti azokat a változtatásokat, amelyeket olyan tranzakciók végeztek, amelyek a hiba pillanatában még folyamatban voltak.

A motor visszafelé iterál a hiányos tranzakciók rekordjain.

Írási undo: a WAL-ban tárolt korábbi képből visszaállítja az eredeti adatokat.

Allokációs undo: meghívja az undoAllocation műveletet, hogy a blokkok visszakerüljenek a PersistentAllocator szabadlistáiba.

Konzisztenciaellenőrzés és javítás

Az ARIES fázisok után a motor véglegesítési feladatokat hajt végre. Ellenőrzi a HeapHeader és az AllocatorMetadata integritását. Ha a helyreállítási fázisok meghiúsulnak vagy kupacsérülést észlel, a rendszer javítási módba válthat. Ha a kupac konzisztens, meghívja a finalizeRecovery függvényt, amely törli a dirty jelzőt, checkpointot indít a WAL csonkolására, majd fsync-kel biztosítja a helyreállítási módosítások tartósságát.

CrashSimulator tesztsegédprogram

A test/crash_test.zig fájlban található CrashSimulator fontos eszköz a RecoveryEngine robusztusságának igazolására. A CrashInjector segítségével precíz végrehajtási pontokon szimulál rendszerhibákat.

Hibabefecskendezési pontok

A CrashPhase enumeráció meghatározza azokat a pillanatokat, amikor szimulált összeomlás történhet.

before_wal_write és after_wal_write.

before_heap_write és after_heap_write.

before_flush és after_flush.

before_commit és after_commit.

Szimulációs munkafolyamat

Inicializálás: létrehoz egy új kupacot és WAL-t.

Véletlenszerű műveletek: allokációk és írások sorozatát hajtja végre.

Befecskendezett hiba: az injector.checkCrash meghatározza, hogy az aktuális műveletnél bekövetkezzen-e az összeomlás.

Helyreállítás és ellenőrzés: a szimulátor újranyitja a kupacot, futtatja a RecoveryEngine.recover műveletet, majd az eredményül kapott kupacállapotot összeveti egy expected_state listával annak biztosítására, hogy ne történjen adatvesztés vagy adatsérülés.

Magas szintű API és adatstruktúrák

A magas szintű API réteg a fejlesztői oldalt szolgálja ki a perzisztens adatokkal való munkához. Elrejti a tárolómotor bonyolultságát, például a kézi eltoláskezelést és a nyers tranzakciónaplózást, és ergonomikus Zig konstrukciókat kínál. Ez a réteg kezeli az objektumok életciklusát, típusbiztonságot biztosít a sémaregiszteren keresztül, és perzisztens változatokat ad általános adatstruktúrákból, például tömbökből és térképekből.

Architekturális áttekintés

Az API réteg az alkalmazáslogika és az alapvető tárolókomponensek, például az allokátor, a tranzakciókezelő és a GC között helyezkedik el. A magas szintű műveleteket, például tömbelem-hozzáfűzést vagy struktúraszerkesztést tranzakcionális írásokká és referenciaszám-frissítésekké fordítja.

PersistentStore és fogantyúk

A PersistentStore a fejlesztők elsődleges belépési pontja. Összehangolja a memóriakezelést a PersistentAllocatorral és az ACID garanciákat a TransactionManagerrel.

A Handle T egy RAII stílusú interfész perzisztens objektumok eléréséhez. Kezeli a PersistentPtr lemezes eltolások és a natív Zig mutatók, azaz a memórialeképezett címek közötti átmenetet. A fogantyúk saját EditMode állapotot követnek, hogy eldöntsék, automatikusan induljon-e tranzakció, amikor adat módosul az edit metóduson keresztül.

Kulcskomponensek

Handle T: biztonságos hozzáférést nyújt a perzisztens memóriához. EditMode segítségével kezeli a konkurenciát és a tranzakciós állapotot. Az üzemmód lehet read, write vagy exclusive.

ResidentObjectTable: a store által fenntartott gyorsítótár, amely elkerüli a redundáns mutatófeloldásokat és segíti a referenciaszámlálást.

RAII szemantika: a handle deinit metódusa biztosítja, hogy bármely függő dirty állapot elköteleződjön vagy a tranzakciós szabályzatnak megfelelően kezelődjön.

PersistentStore, Handle és gyűjtemények

A src/api.zig modul adja a perzisztens adatokkal való interakció elsődleges magas szintű interfészét. A PersistentStore az erőforráskezelés központi koordinátora. Elvégzi a magas szintű allokációt, feloldást és gyökérkezelést.

PersistentStore műveletek

init: összekapcsolja az allokátort, a tranzakciókezelőt és a rezidens objektumtáblát.

allocate: lefoglal egy perzisztens memóriablokkot, és PersistentPtr értéket ad vissza.

resolve: natív Zig mutatóvá alakít egy PersistentPtr értéket, felhasználva a ResidentObjectTable gyorsítótárát.

setRoot: frissíti a kupac gyökérmutatóját, amely belépési pont az objektumgráf bejárásához.

write: tranzakcionális bájtpuffer-írást hajt végre meghatározott perzisztens helyre.

Handle T és EditMode életciklus

A Handle T egy PersistentPtr köré épülő RAII burkolat. Kezeli az objektumhozzáférés életciklusát, beleértve a tranzakciónaplózást és a dirty page követést.

Feloldás: amikor a get meghívódik, a fogantyú a PersistentStore segítségével natív mutatóvá oldja fel a PersistentPtr értéket.

Módosítás: az edit meghívása magasabb módosítási szintre emeli a fogantyút. Ha korábban read módban volt, write módra vált. Fontos, hogy az edit meghívja a transaction_manager.recordWrite műveletet, hogy az eredeti állapot bekerüljön a WAL-ba, mielőtt bármilyen változás történik.

Perzisztencia: a dirty jelző követi, hogy az objektum módosult-e. Commit hívásakor, illetve deinit során, ha az objektum dirty, a fogantyú a natív memóriát visszaflush-olja a perzisztens kupacba.

Perzisztens gyűjtemények

PersistentArray T: dinamikusan átméreteződő tömb, amely T típusú elemeket tárol. Ha a len meghaladja a capacity értéket, a grow függvény meghívódik, és a store.reallocate műveletet használja. Az elemek elérése a bázis PersistentPtr értéktől számolt eltolással történik.

PersistentMap K V: hash láncolást megvalósító perzisztens hash map. Egy bucket tömbből és Entry struktúrákból áll. Minden bejegyzés kulcsot, értéket, hash értéket és next_offset mezőt tartalmaz az ütközések kezelésére. A struktúrában szereplő összes mutató eltolás vagy PersistentPtr formában tárolódik a címtér-függetlenség érdekében.

Schema Registry és objektummigráció

A Schema Registry futásidejű reflexiós rendszer, amely rögzíti és verziózza a perzisztens objektumok elrendezését. Lehetővé teszi, hogy a rendszer alkalmazásfrissítések között is megőrizze a bináris kompatibilitást, és mechanizmust ad az objektummigrációhoz, ha az adatstruktúrák megváltoznak.

Áttekintés

A rendszer a Zig comptime képességeit használja a struktúraelrendezések introspekciójára és központi SchemaRegistry-ben való tárolására. Ezt a regisztert az objektumok integritásának ellenőrzésére, bináris szerializálásra és migrációs visszahívások futtatására használja, amikor egy régebbi sémájú objektumhoz a PersistentHeapből egy újabb sémaverzióval próbálnak hozzáférni.

Adatstruktúrák

FieldInfo: az egyes struktúramezők tulajdonságait rögzíti, például a nevet, a FieldKind értéket, az eltolást, a méretet és az igazítást.

StructInfo: a teljes típus fejlécét adja, sémaazonosítóval, teljes mérettel és checksum mezővel.

FieldKind: enumeráció, amely az alaptípust reprezentálja, például int, float, pointer vagy struct.

Schema regisztráció

A regisztráció futásidőben történik, de comptime információra támaszkodik a típusadatok kinyeréséhez.

Típusintrospekció: az @typeInfo T segítségével ellenőrzi, hogy a típus struct-e.

Mezők kinyerése: inline for ciklussal bejárja a mezőket és rögzíti az eltolásokat, méreteket.

Karakterlánc-pooling: a mező- és struktúraneveket közös string_pool gyűjteményben tárolja az allokációk csökkentésére.

Checksum generálás: a computeStructChecksum egyedi lenyomatot készít az elrendezésről.

A fieldTypeToKind függvény a Zig típusokat a FieldKind enumerációra képezi le. Az Int típus .int vagy .uint, a Float .float, a Pointer .pointer, az Optional .optional, a Struct pedig .struct_ formában jelenik meg.

Objektummigráció

A migráció az adatok átalakítását jelenti régi sémaelrendezésből új sémára. Akkor indul, amikor az ObjectHeaderben tárolt schema_id nem egyezik a típushoz jelenleg regisztrált azonosítóval.

migrateObject folyamat

Azonosítás ellenőrzése: ha az azonosítók megegyeznek, a függvény adatmásolatot ad vissza.

Pufferallokáció: új puffert foglal az új séma mérete alapján.

Alapértelmezett másolás: a régi és az új méret közös tartományát memcpy-vel másolja.

Egyedi visszahívás: ha az adott régi és új sémapárhoz MigrationFn van regisztrálva, akkor azt futtatja a bonyolultabb átalakítások kezelésére.

Kompatibilitási elemzés

A compareSchemas függvény programozottan meg tudja állapítani, hogy két séma kompatibilis-e.

Bináris szerializálás

A regiszter önmaga perzisztálásához a rendszer függvényeket ad a memóriabeli SchemaRegistry lapos bináris formátummá alakítására.

serializeSchema: a StructInfo fejlécet, majd a FieldInfo tömböt és a kapcsolódó neveket bájtpufferbe írja.

deserializeSchema: bájtpufferből rekonstruál SchemaEntry értéket, ellenőrizve a SchemaMagic és SchemaVersion konstansokat.

Memóriabiztonság és szemétgyűjtés

A pheap memóriabiztonsága többrétegű megközelítéssel valósul meg, amely a determinisztikus életciklus-kezelést robusztus biztonsági primitívekkel ötvözi. A rendszer biztosítja, hogy a perzisztens objektumok csak akkor kerüljenek felszabadításra, amikor már nem elérhetők, miközben védi a lemezen tárolt adatok integritását és bizalmasságát.

A memóriakezelési alrendszer áthidalja a nyers perzisztens tárolás és a magas szintű objektumgráfok közötti szakadékot. A RefCountGC kezeli az objektumok életciklusát, a SecurityManager pedig a titkosítást és a hardveresen támogatott integritást.

Referencia-számlálásos GC és particionált gyűjtés

A RefCountGC az objektumélettartamok elsődleges hatósága. A kupac minden objektumát ObjectHeader előzi meg, amely ref_count mezőt tartalmaz.

Életciklus-műveletek

Az életciklus-változások tranzakcionálisan rögzítődnek, hogy összeomlások esetén is konzisztens maradjon az állapot.

incrementRefCount: növeli a referenciaszámot és ref_count_inc rekordot fűz a WAL-hoz.

decrementRefCount: csökkenti a referenciaszámot. Ha az érték eléri a nullát, a freeObjectGraph rekurzív objektumgráf-törlést indít.

freeObjectGraph: az objektumok rekurzív megsemmisítését kezeli. A mély objektumláncok okozta verem túlcsordulás elkerülésére depth paramétert és MAX_RECURSION_DEPTH korlátot használ.

GCObjectInfo

A GC tetszőleges struktúrák bejárásához a GCObjectInfo struktúrát használja.

ref_count: az aktuális hivatkozások száma.

schema_id: az objektum sémaregiszter-bejegyzése.

scan_fn_offset: annak a függvénynek az eltolása, amely megtalálja a gyermekmutatókat.

finalize_fn_offset: a destruktor vagy takarítófüggvény eltolása.

Ciklusgyűjtés, jelölés és söprés

Bár a referenciaszámlálás kezeli a lineáris életciklusokat, nem képes felszabadítani az önmagukra visszahivatkozó ciklusokat. A RefCountGC runCollection művelete globális jelöléses söprést hajt végre.

A gyűjtés folyamata

Gyökérazonosítás: a gyűjtő a kupac gyökérmutatójából indul.

Jelölési fázis: GCContext segítségével követi a marked objektumokat hash mapben és worklist listában.

Bejárás: minden objektumnál meghívja a scan_fn függvényt, hogy megtalálja a beágyazott PersistentPtr példányokat.

Söprés: minden olyan objektumot, amely szerepel az object_registry-ben, de nem volt elérhető a jelölési fázis során, szivárgásnak tekint és felszabadít.

PartitionedGC és inkrementális gyűjtés

A hosszú stop the world szünetek elkerülése érdekében a pheap particionált gyűjtést is támogat. A kupac logikailag szegmensekre van osztva, és a GC ezeket fokozatosan tudja feldolgozni.

Cycle breakers

A cycle_breakers lista olyan mutatókat tárol, amelyeket a felhasználó vagy a rendszer potenciális belépési pontként azonosított ciklikus struktúrákhoz. A runCollection ezeket előnyben részesíti az összetett gráfok hatékony feloldása érdekében.

WAL integráció

Minden GC művelet, például Mark, DecRef és Free, GCOperationDescriptor köré van csomagolva. A leíró tartalmazza a művelettípust és CRC32c checksumot az integritás biztosítására.

GC statisztikák és megfigyelés

A GCStats szerkezet követi a gyűjtési ciklusok hatékonyságát.

objects_scanned: a jelöléses söprés során bejárt objektumok teljes száma.

cycles_detected és cycles_broken: a ciklikus struktúrák begyűjtésének mutatói.

total_time_ns: a GC rutinfutásokra fordított kumulatív idő.

Biztonság: titkosítás és integritásellenőrzés

A SecurityManager és az IntegrityVerifier erős adatvédelmi mechanizmusokat biztosít, beleértve a nyugalmi állapotú hitelesített titkosítást és a Merkle-fa alapú integritásellenőrzést. Ezek biztosítják, hogy az adatok bizalmasak, hitelesek és védettek maradjanak az offline manipulációval vagy hardveres bithibákkal szemben.

Kriptográfiai primitívek

A pheap két fő AEAD algoritmust támogat, amelyeket az EncryptionAlgorithm enumeráció választ ki.

AES 256 GCM: akkor használatos, ha a hardveres gyorsítás, például az AES NI, elérhető.

ChaCha20 Poly1305: nagy teljesítményű szoftveres alternatíva olyan platformokon, ahol nincs speciális AES utasítás.

Kulcskezelés és levezetés

A rendszer hierarchikus kulcsszerkezetet alkalmaz a SecurityManager kezelésében.

Master Key: 32 bájtos gyökérbizalmi kulcs.

Region Keys: a kupac egyes szegmenseinek titkosítására használt származtatott kulcsok.

HKDF SHA256: egyedi alkulcsokat generál a mesterkulcsból, megakadályozva a kulcsok újrahasználatát különböző kontextusok között.

Titkosítás megvalósítása

A SecurityManager.encrypt EncryptedRegion értéket állít elő, amely a titkosított szöveget, egy 12 bájtos nonce-t és egy 16 bájtos hitelesítő taget tartalmaz.

Nonce generálás

A nonce újrafelhasználási támadások megakadályozása érdekében a pheap atomi nonce_counter számlálót használ. A generateNonce ezt a számlálót véletlen előtaggal kombinálja az egyediség biztosítására újraindítások között is.

Integritásellenőrzés

Az IntegrityVerifier a memórialeképezett régiók fölött Merkle-fát épít, hogy ellenőrizze, nem sérült-e vagy nem manipulálták-e a kupacot.

A verifikátor blokkokra osztja a kupacot, mindegyikről hash értéket számol, majd ezeket faalakba rendezi úgy, hogy a gyökér hash az egész kupac állapotát reprezentálja. A hash függvény SHA 256. Inicializáláskor vagy pillanatkép-visszaállításkor a rendszer újraszámolja a fát, és a gyökérértéket összehasonlítja egy TPM-ben vagy biztonságos fejlécben tárolt lezárt értékkel.

TPM2 integráció

A TPM2Interface lehetővé teszi a mesterkulcs vagy a Merkle-gyökér meghatározott Platform Configuration Register értékekhez kötött lezárását. Ez biztosítja, hogy a kupac csak ismert jó rendszerindítási állapot esetén legyen visszafejthető.

Kulcsforgatás és karbantartás

A SecurityManager kulcsforgatást is támogat a közös kulccsal titkosított adatmennyiség korlátozására.

Új kulcs generálása.

A titkosított régiók visszafejtése a régi kulccsal, majd újratitkosítása az új kulcsazonosítóval.

A régi kulcsok törlése a region_keys térképből és biztonságos nullázása.

Konkurencia primitívek

A pheap robusztus szálbiztonsági infrastruktúrát kínál memóriabeli koordinációhoz és perzisztens állapotkezeléshez. Ezek a primitívek a src/concurrency.zig állományban találhatók, és hibrid stratégiákat valósítanak meg, amelyek az alacsony késleltetésű pörgetést a kernel szintű futex várakozással kombinálják különböző versengési helyzetek optimalizálására.

PMutex: hibrid spin futex mutex

A PMutex perzisztens használatra képes kölcsönös kizárási primitív. Először megpróbálja a zárat pörgetéssel megszerezni, meghatározott számú iteráció erejéig, majd ha ez sikertelen, std.Thread.Futex.wait alapú alvásra áll át.

Állapotok

STATE_UNLOCKED 0.

STATE_LOCKED 1.

STATE_CONTENDED 2.

Spin fázis

A lock meghívásakor a szál a spin_count számú iterációig atomikus cmpxchgStrong művelettel próbálja megszerezni a zárat.

Futex fázis

Ha a pörgetés nem sikerül, az állapot STATE_CONTENDED-re vált, és a szál futex várakozásra megy, amíg a tulajdonos fel nem oldja a zárat.

Tulajdonjog

Az owner mező a jelenlegi szál azonosítóját tárolja. Ez lehetővé teszi a holtpontok felismerését, ha egy szál újra megpróbál megszerezni egy már birtokolt zárat.

A PMutex extern struct formában van definiálva, hogy stabil bináris elrendezést biztosítson perzisztens tároláshoz, magic számokkal és verziózással.

PRWLock: íróprioritásos olvasó író zár

A PRWLock írókat előnyben részesítő olvasó író zárat valósít meg. Ez kritikus a pheap-ben, mert az író tranzakcióknak gyorsan kell commitolniuk a WAL erőforrások felszabadításához.

Olvasási megszerzés

Egy olvasó akkor szerezheti meg a zárat, ha az állapot unlocked. Ha az állapot read locked, az olvasó csak akkor csatlakozhat, ha nincs várakozó író. Ha író vár, az olvasónak blokkolnia kell.

Írási megszerzés

Egy író növeli a write_waiters számlálót és megpróbálja write locked állapotba tenni a zárat. Meg kell várnia, amíg minden aktív olvasó száma nullára csökken.

Feloldás

Amikor az író feloldja a zárat, az állapot unlocked lesz, és először a várakozó írókat, majd az olvasókat ébreszti fel.

PCondVar: generációalapú feltételes változó

A PCondVar a konkrét állapotváltozásokhoz kötött szinkronizációt kezeli. Egy generációszámlálót használ az elveszett ébresztés problémájának megoldására perzisztens környezetben.

wait: elmenti az aktuális generációt, feloldja a kapcsolódó PMutex zárat, majd futex-szel alszik, amíg a generáció növekedése be nem következik.

signal: növeli a generációt és egy várakozót ébreszt.

broadcast: növeli a generációt és minden várakozó szálat felébreszt.

RAII őrök

A pheap RAII őröket biztosít a biztonságos zárkezeléshez. Ezek automatikusan feloldják a zárakat, amikor kikerülnek a hatókörből.

LockGuard a PMutex zárhoz tartozik és a mutex.unlock művelettel old fel.

ReadGuard a PRWLock olvasási zárához tartozik és a rw_lock.unlockRead művelettel old fel.

WriteGuard a PRWLock írási zárához tartozik és a rw_lock.unlockWrite művelettel old fel.

Pillanatképek, javítás és eszközök

A pillanatkép, javítás és eszközök alrendszer azt az operatív infrastruktúrát biztosítja, amely a pheap példány hosszú távú egészségének és tartósságának fenntartásához szükséges. Miközben az alapvető runtime kezeli az ACID tranzakciókat és a memóriakezelést, ezek az eszközök sávon kívüli mechanizmusokat adnak inkrementális mentésekhez, integritásauditokhoz és katasztrófa-helyreállításhoz.

A SnapshotManager és a HeapRepair mélyen együttműködnek a PersistentHeap és a PersistentAllocator belső struktúráival, míg a HeapInspector nem romboló, csak olvasható nézetet biztosít a rendszerállapotról.

Snapshot Manager

A Snapshot Manager felel az időpillanat-szerű, inkrementális kupacreprezentációk rögzítéséért. OS szintű memóriavédelmet, azaz mprotect-et használ az oldalszintű módosítások követésére, lehetővé téve a hatékony mentéseket, állapotreplikációt és a Merkle-fa alapú integritásellenőrzést.

DirtyPageTracker

A DirtyPageTracker a heapet lapokra osztja és bitkészlettel követi, mely lapok módosultak.

Inicializáláskor egy bitképet foglal, ahol minden bit egy lapot képvisel.

A protectPages függvény a kupac lapjait csak olvashatóvá teszi. Ez szegmentációs hibát okoz, ha a futtatókörnyezet írni próbál rájuk.

Írás észlelésekor az unprotectPage helyreállítja az írási jogot, és atomi Or művelettel megjelöli a megfelelő bitet.

SnapshotHeader

magic: 0x534E5053.

snapshot_id: monoton növekvő azonosító.

heap_size: a kupac teljes mérete a rögzítéskor.

root_offset: a perzisztens gyökérobjektum eltolása.

merkle_root: a Merkle-fa gyökérhash-e.

checksum: a fejlécmezők CRC32c értéke.

Merkle-fa integritás

Az adatromlás észlelésére a kezelő Merkle-fát számít a dirty lapok fölött. Minden MerkleNode a gyermekeinek vagy az adatblokk saját hash-ét tárolja. A végső merkle_root a fejlécben tárolódik, és a verifySnapshot művelet ezt használja a teljes kupacállapot hitelesítésére.

Visszaállítás és ellenőrzés

restoreSnapshot során a rendszer validálja a SnapshotHeader értékeit, betölti a page_bitmap állapotot, csak a dirty-ként jelölt lapokat másolja vissza a PersistentHeap memóriaterébe, majd visszaállítja a gyökérmutatót a snapshotban tárolt root_offset és UUID alapján.

verifySnapshot során a rendszer újraszámolja a jelenlegi kupacadatok Merkle-fáját, és a kapott gyökeret összehasonlítja a SnapshotHeader merkle_root mezőjével. Ha a checksum vagy a Merkle-gyökér nem egyezik, a snapshot sérültnek minősül.

Heap Repair Tool, pheap-repair

A HeapRepair eszközt a perzisztens kupacon belüli szerkezeti sérülések diagnosztizálására és kijavítására tervezték. Elkülönült fázisokban működik, a HeapHeader vizsgálatával indul, majd az AllocatorMetadata-n és az egyedi objektumgráfokon halad végig.

Javítási képességek

Fázisalapú javítás: egymást követően javítja a fejlécet, az allokátor metaadatait, a szabadlistákat és az objektumokat.

Szabadlista újjáépítés: a rebuildFreeLists teljes lineáris kupacbejárást végez az elveszett szabad blokkok visszanyerésére.

Auditnyom: minden javítási művelet RepairAction bejegyzésként naplózódik, lehetővé téve a dry run elemzést a lemezmódosítás előtt.

Az eszköz támogat agresszívebb helyreállítási módokat is, amelyek a strukturális hibák javítását és a szabadlisták újraszervezését szolgálják.

Heap Inspection Tool, pheap-tool

A pheap-tool csak olvasható diagnosztikai eszköz, amely mély betekintést ad egy perzisztens kupac belső állapotába anélkül, hogy módosítaná annak tartalmát. A c/inspect.zig fájlban definiált HeapInspector struktúrát használja kupacfejlécek elemzésére, allokációs statisztikák vizsgálatára, lineáris objektumvizsgálatra és a WAL ellenőrzésére.

HeapInspector architektúra

A HeapInspector a vizsgálóeszköz elsődleges motorja. Olyan módban inicializálja a PersistentHeapet, amely biztonságos szerkezeti elemzést tesz lehetővé, és olyan metódusokat kínál, amelyek közvetlenül a parancssori alműveletekhez kapcsolódnak.

inspectHeader: érvényesíti a HeapHeader értékeket és az ellenőrzőösszegeket.

inspectStats: jelentést ad a kupackihasználtságról és az allokátor állapotáról.

inspectObjects: lineáris vizsgálatot végez a kupacterületen.

inspectWAL: feldolgozza a WAL fájlt tranzakciós rekordokért.

validateHeap: szerkezeti integritás-ellenőrzést végez.

Diagnosztikai funkciók

inspectHeader kimutatja a Pool UUID, a tranzakcióazonosító és a dirty flag állapotát. Meghívja a hdr.computeChecksum műveletet és összeveti az eredményt a tárolt hdr.checksum értékkel a fejlécsérülés felismeréséhez.

inspectStats meghatározza a kupac base_addr címét, pointer casttal megtalálja az AllocatorMetadata struktúrát a HEADER_SIZE eltolás után, és megjeleníti a total allocated és total freed bájtokat, a kupackihasználtság százalékát és a méretosztályok számát.

inspectObjects nyers lineáris memóriaszkennelést végez. Az AllocatorMetadata végén indul, minden 64 bites határt megvizsgál OBJECT_MAGIC vagy FREE_MAGIC jelekre, és minden talált objektumnál közli a schema_id, ref_count és az isFreed, isPinned jelzők állapotát.

inspectWAL csak olvasható módban inicializálja a WAL-t és kiírja a head_offset, tail_offset és last_checkpoint értékeket. Ez megszakadt tranzakciók hibakereséséhez és annak ellenőrzéséhez fontos, hogy a RecoveryEngine megtisztította-e a naplót.

Parancssori alműveletek

header: UUID, verzió és checksum állapot megjelenítése.

stats: allokátorhasználat és töredezettségi mutatók megjelenítése.

objects: a kupacban talált összes objektum fejlécének kilistázása.

wal: az előreíró napló állapotának kiírása.

validate: teljes integritásellenőrzés futtatása, ellenőrzőösszegekkel és szerkezeti vizsgálattal.

Integritás és validáció

A validateHeap ellenőrzi a magic számokat, az ellenőrzőösszegeket és a dirty állapotot. Ha a kupacot nem megfelelően zárták le, a dirty jelző alapján jelzi, hogy pheap-repair vagy a RecoveryEngine futtatására lehet szükség.

GPU számítás és cache flush infrastruktúra

A pheap hardvergyorsítási alrendszere nagy teljesítményű számítási hidat biztosít a perzisztens tárolás és a gyorsító hardver között. A Futhark adatpárhuzamos nyelvet használja kernelvégrehajtásra, dinamikus könyvtárbetöltéssel és strukturált állapotgéppel a hoszt és az eszköz szinkronizálásához.

A gyorsító infrastruktúra két fő részre oszlik. A GPUContext a számítási környezetet, a kernelkönyvtár életciklusát és az eszközmemória-kezelést adja. A cache flush és perzisztens memória primitívek pedig biztosítják, hogy a gyorsító által előállított vagy módosított adatok megfelelő sorrendben és tartósan kerüljenek a tárolóeszközre.

GPU Context és Futhark integráció

A GPUContext a GPU műveletek központi koordinátora. Kezeli a kernelkönyvtár életciklusát, nyomon követi a lefoglalt eszközmemóriát és regisztert tart fenn az elérhető GPU kernelekről.

Inicializálás és kernelbetöltés

A kontextus a lefordított Futhark megosztott könyvtár betöltésével inicializálódik a std.DynLib.open segítségével. Sikeres betöltés után feltölt egy StringHashMap alapú GPUKernelInfo regisztert, amely a kernelneveket, bemeneti típusokat és kimeneti típusokat tartalmazó metaadatokat tárolja.

Adatreprezentáció: GPUValue és GPUArray

A Zig típusrendszere és a Futhark elvárásai közötti híd létrehozására a pheap tagged uniont és generikus tömbburkolatot használ.

GPUValue: olyan tagged union, amely skalárokat és tömbtípusokat támogat.

GPUArray T: olyan generikus struktúra, amely hosztoldali adat szeletet és opcionális device_ptr eszközmutatót kezel a GPU-n rezidens memóriához.

Számítási állapotgép és életciklus

Idle: kezdeti állapot, a kontextus létrejött, de nincs aktív kernel.

Preparing: a hosztadatok lefoglalása és másolása az eszközre.

Executing: a Futhark kernel meghívása a dinamikusan betöltött könyvtáron keresztül.

Synchronizing: várakozás a GPU befejezésére és az eredmények visszahozása.

Committed: az eredmények elérhetők a hoszton, és az eszközmemória felszabadul.

Memóriakezelés

A GPUContext az összes eszközoldali allokációt allocated_arrays listában tartja nyilván. Így még sikertelen kernelvégrehajtás esetén is képes tömeges takarítást végezni a freeAllArrays segítségével a kontextus megszüntetésekor.

Futhark integráció

A c/compute.fut adatpárhuzamos primitívek könyvtárát tartalmazza olyan nagy léptékű műveletekhez, amelyek a memóriába lapozott perzisztens adatokon dolgoznak.

Támogatott műveletek

Redukciók: sum_array, find_max, dot_product.

Transzformációk: map_add, vector_scale, softmax, relu.

Mátrixműveletek: matrix_multiply, transpose, reshape_1d_to_2d.

Statisztikai műveletek: mean_array, variance_array, standard_deviation.

Cache flush és perzisztens memória primitívek

Ez a rész az alacsony szintű infrastruktúrát írja le, amely az adatok tartósságát és a hardveresen támogatott biztonságot biztosítja. A rendszer elrejti az x86_64 és az AArch64 architektúrák közötti különbségeket, primitíveket biztosít a cache sorok kezeléséhez, és C interfészt valósít meg a TPM műveletekhez.

Cache-kezelés és utasításválasztás

A tartóssági réteg magja a c/cache_flush.h állományban van. Egységes interfészt biztosít a CPU cache-ek perzisztenciatartományba történő flush-olásához. x86_64 rendszereken a könyvtár felismeri és használja a leghatékonyabb elérhető utasításokat, például a CLWB, CLFLUSHOPT vagy a régebbi CLFLUSH utasítást.

Hardveres primitívek

_clwb: visszaírja a cache sort a memóriába anélkül, hogy érvénytelenítené azt.

_clflushopt: optimalizált, nem rendezett flush utasítás.

_sfence: biztosítja, hogy az összes megelőző store és flush művelet globálisan látható legyen a továbblépés előtt.

_mfence: teljes memóriagát, főként a régi CLFLUSH műveletekhez.

Egységes flush interfész

A flush_range egyetlen hívássá absztrahálja ezeket az utasításokat, és 64 bájtos lépésekben iterál a memórián, ami a szabványos cache sorméret.

cache_flush x86_64 rendszeren CLWB ciklust és SFENCE-et használ.

cache_flush_opt x86_64 rendszeren CLFLUSHOPT ciklust és SFENCE-et használ.

cache_flush AArch64 rendszeren dc cvac, dsb sy és isb utasításokat használ.

Platformközi OS absztrakciók

A CPU utasításokon túl a pheap operációs rendszer szintű burkolófüggvényeket is biztosít memórialeképezéshez és szinkronizáláshoz.

map_persistent: fájlleírót képez le a folyamat címtartományába mmap vagy Windows esetén MapViewOfFile segítségével.

persistent_sync: a fájlpuffereket lemezre flush-olja. Linuxon fdatasync, macOS-en F_FULLFSYNC, Windowson FlushFileBuffers szolgál erre.

persistent_msync: adott memórialeképezett tartományt szinkronizál a háttértárral.

Flush batching

A pheap flush_batch_t struktúrát is ad a nagy gyakoriságú frissítések optimalizálására. Ez több dirty tartomány összegyűjtését és egyetlen körben történő flush-olását teszi lehetővé, csökkentve az ismételt memóriagátak költségét.

TPM2 hardveres biztonsági interfész

A c/tpm.c C interfészt valósít meg a Trusted Platform Module 2.0 eléréséhez. Ezt a SecurityManager használja titkosítási kulcsok platformállapotokhoz kötött lezárására.

tpm2_context_t: az ESYS és a TCTI állapotát tartja karban.

tpm2_init: betölti a TCTI loadert és inicializálja az ESYS környezetet.

tpm2_read_pcr: kiolvassa egy meghatározott PCR regiszter kivonatát a rendszerindítási állapot ellenőrzéséhez.

tpm2_seal: úgy titkosít adatot, jellemzően mesterkulcsot, hogy az csak akkor legyen visszafejthető, ha az aktuális PCR értékek megfelelnek a lezáráskor megadott maszk feltételeinek.

Memóriasorrend és tartóssági sorrend

A perzisztencia szigorú műveleti sorrendet igényel. A könyvtár olyan primitíveket is biztosít, amelyek nem perzisztens memóriasorrendezéshez, például szinkronizációhoz szükségesek.

store_release: sfence végrehajtása 64 bites tárolás előtt, hogy a korábbi írások láthatóvá váljanak.

load_acquire: 64 bites betöltés, majd sfence, hogy a későbbi olvasások ne rendeződhessenek a betöltés elé.

Tesztelés és benchmarking

A pheap minőségbiztosítási infrastruktúráját úgy tervezték, hogy igazolja a rendszer fő ígéreteit: az adatok tartósságát áramkimaradásokon át, valamint a nagy teljesítményű tranzakcionális áteresztőképességet. Az infrastruktúra két fő területre oszlik: determinisztikus összeomlásszimuláció az ARIES stílusú helyreállítás igazolására és átfogó benchmark csomag a késleltetés, áteresztőképesség és írási erősítés mérésére.

A tesztarchitektúra összeköti az alacsony szintű tárolóprimitíveket a magas szintű tranzakcionális garanciákkal. Dedikált CrashInjector eszközt használ hibabefecskendezéshez és BenchmarkSuite csomagot a teljesítményprofilozáshoz.

Összeomlás és perzisztencia tesztcsomag

Az összeomlástesztelő keretrendszer biztosítja, hogy a RecoveryEngine a kupacot konzisztens állapotba tudja visszaállítani, függetlenül attól, hogy az írási életciklus mely pontján következik be hiba.

A CrashInjector figyeli a végrehajtást és meghatározott CrashPhase pontokon, például before_wal_write, after_wal_write vagy before_commit állapotokban szimulált hibákat vált ki. A CrashSimulator ezt automatizálja: több ezer iteráción át véletlenszerű összeomlási pontokat generál, majd ellenőrzi, hogy minden helyreállítási kísérlet konzisztens kupacállapotot eredményez-e.

Kulcskomponensek

CrashInjector: a current_iteration és current_operation mezők segítségével should_crash jelzőket állít elő.

PersistenceTestSuite: névvel ellátott tesztek gyűjteménye, amelyek a tranzakciós atomicitást és a WAL visszajátszás integritását ellenőrzik.

CrashTestResult: olyan mutatók készlete, amelyek a sikeres és sikertelen helyreállítások, valamint az észlelt adatsérülések számát rögzítik.

Crash és perzisztencia tesztcsomag részletei

A CrashPhase enumeráció a következő kockázatos pontokat határozza meg: before_wal_write, after_wal_write, before_heap_write, after_heap_write, before_flush, after_flush, before_commit és after_commit.

A CrashSimulator munkafolyamata friss kupac és WAL létrehozásával kezdődik, ezt véletlenszerű allokációk és írások követik, majd az injector ellenőrzi, hogy az adott ponton összeomlásnak kell-e történnie. Újranyitás után a RecoveryEngine.recover lefut, és a rendszer az expected_state állapottal hasonlítja össze a visszaállított kupacot. A cél annak igazolása, hogy részleges írás, megszakadt commit vagy WAL közbeni hiba esetén se vesszen el adat és ne sérüljön a szerkezet.

Teljesítmény-benchmarking

A benchmarking infrastruktúra részletes rálátást ad a tárolómotor késleltetési profiljaira. A BenchmarkSuite különböző terheléseket futtat a PersistentHeapen és a PersistentAllocatoron.

A benchmarkok BenchmarkConfig segítségével konfigurálhatók, amely meghatározza például a warmup_iterations, object_size és read_ratio paramétereket. Az eredményeket BenchmarkResult objektumok tartalmazzák, áteresztőképességi és időzítési statisztikákkal.

Workload típusok

Allocation benchmark: alloc és free ciklusokat mér.

Write benchmark: nyers heap.write teljesítményt mér rögzített eltoláson.

Read benchmark: nyers heap.read teljesítményt mér rögzített eltoláson.

Transaction benchmark: beginTransaction, appendRecord és commitTransaction műveleteket mér.

Mixed workload benchmark: olvasás és írás arányát szimulálja a BenchmarkConfig.read_ratio alapján.

Bemelegítés és iterációk

Minden benchmark konfigurálható számú warmup iterációt végez a kezdeti fájlrendszer-allokációs és cache költségek kiegyenlítésére. Csak az ezt követő iterációk számítanak bele a min, max és avg késleltetésekbe.

Késleltetésmérés és hisztogram

A pheap LatencyHistogram szerkezetet használ az egyes műveleti idők eloszlásának rögzítésére, ami a farok-késleltetések azonosításához kritikus. A hisztogram logaritmikus vödrözést alkalmaz, így a nanomásodpercektől a másodpercekig terjedő tartományt nagy memóriaigény nélkül tudja lefedni.

Írási erősítés mutató

Az írási erősítés a WAL hatékonyságának egyik kulcsmérője. Az érték azt mutatja, mennyi adat íródik a WAL-ba a kupacban ténylegesen allokált vagy frissített adatmennyiséghez képest.

Képlet: WAL méretnövekedés osztva a kupacba allokált adatmérettel.

Jelentőség: a magas írási erősítés túlzott metaadatnaplózásra vagy nem hatékony WAL rekordformátumokra utalhat, ami telítheti az I O sávszélességet.

Jelentéskészítés és kimenet

A BenchmarkResult a következőket tartalmazza.

Áteresztőképesség: ops_per_sec és throughput_mb_sec.

Késleltetési statisztikák: avg_time_ns, min_time_ns és max_time_ns.

Konfigurációs környezet: a használt BenchmarkConfig paramétereit is megőrzi, hogy különböző hardver- vagy szoftververziók között összehasonlítható maradjon a mérés.

Az eszközök build integrációja

pheap-bench: teljesítménymérő futtatására szolgál, és CSV vagy JSON metrikákat ad ki.

crash-test: véletlenszerű hibabefecskendezési ciklusokat hajt végre.

Szójegyzék

Ez az oldal átfogó szójegyzéket ad a kódbázisspecifikus kifejezésekről, rövidítésekről, mágikus konstansokról és területi fogalmakról, amelyeket a pheap perzisztens memóriarendszer használ. Technikai hivatkozásként szolgál az újonnan csatlakozó mérnökök számára az alapvető megvalósítási részletek és adatfolyam megértéséhez.

Alapvető tárolási fogalmak

PersistentHeap

A memórialeképezett fájlt képviselő perzisztens tárolókészlet elsődleges kezelőstruktúrája. Kezeli az mmap régió életciklusát, a dirty page követést a pillanatképekhez, valamint az alacsony szintű olvasási és írási műveleteket.

PersistentPtr

Helyfüggetlen mutató, amelyet a kupac objektumaira való hivatkozásra használnak. A hagyományos virtuális memóriamutatókkal ellentétben a PersistentPtr folyamat-újraindítások és eltérő címtér-leképezések között is érvényes marad.

RelativePtr és RelativeSlice

Perzisztens mutató tömörített változata, amelyet lemezen tárolt struktúrákban a helytakarékosság érdekében használnak. Bittagelést alkalmaz az inline értékek támogatására.

INLINE_FLAG: 0x80000000, amellyel a rendszer megkülönbözteti a mutatót a beágyazott 15 bites értéktől.

HeapHeader

A metaadatblokk, amely a kupacfájl legelején, a 0 eltoláson helyezkedik el. Nélkülözhetetlen információkat tartalmaz a kupac azonosításához és ellenőrzéséhez.

HEAP_MAGIC: ZIGPHEAP.

Kulcsmezők: pool_uuid, heap_size, used_size és root_offset, amely a perzisztens objektumgráf belépési pontjára mutat.

Tranzakciós és helyreállítási fogalmak

WAL, azaz előreíró napló

Olyan csak hozzáfűzhető napló, amely minden kupacmódosítást rögzít az alkalmazásuk előtt. Ez biztosítja az atomicitást és a tartósságot.

WAL_MAGIC: 0x57414C46.

Tipikus rekordtípusok: begin, commit, write, allocate.

TransactionManager

Magas szintű tranzakciók koordinátora, amely olvasási és írási halmazokat kezel ütközésérzékeléshez, és a WAL-lal működik együtt. A tranzakciók tipikus életciklusa active, prepared, committed.

RecoveryEngine

Az a komponens, amely összeomlás után a kupac konzisztenciáját helyreállítja a WAL visszajátszásával. Elemzési, redo és undo fázisokat hajt végre, az elkötelezett tranzakciókat újrajátssza, a befejezetleneket pedig visszagörgeti.

Memóriakezelés és GC

PersistentAllocator

Speciális allokátor, amely a PersistentHeap blokkjait kezeli. Méretosztályokat használ a kis allokációkhoz és best fit stratégiát a nagyokhoz.

AllocatorMetadata az allokációs számlálókat és a szabadlisták fejmutatóit tárolja.

ALLOCATOR_MAGIC: 0x414C4F43.

RefCountGC

Hibrid szemétgyűjtő, amely elsődlegesen referenciaszámlálással végez azonnali visszanyerést, kiegészítve ciklustörő mechanizmussal.

Minden perzisztens objektumot ObjectHeader előz meg, amely ref_count és schema_id mezőt tartalmaz.

Fogalmi megfeleltetések

A tárolási oldalon a PersistentHeap, a HeapHeader, a PersistentPtr és a PersistentAllocator együtt alkotják azt az alapréteget, amely a nyers tárolót tartós objektumtárrá alakítja.

A konkurencia és biztonság területén a szinkronizációs primitívek, a SecurityManager és a SchemaRegistry együtt biztosítják a helyes párhuzamosságot, a titkosítást és a típusok következetességét.
