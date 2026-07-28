library;

import "package:test/test.dart";
import "package:y_crdt/src/lib0/testing.dart" as t;
import "package:y_crdt/src/utils/doc.dart" show fromSubdocsEventData;
import "package:y_crdt/src/utils/transaction.dart";

import 'package:y_crdt/y_crdt.dart' as y;


void main() {
  group('doc', () {
    test('after transaction recursion', () {
      testAfterTransactionRecursion(t.TestCase('doc', 'after transaction recursion'));
    });

    test('origin in transaction recursion', () {
      testOriginInTransaction(t.TestCase('doc', 'origin in transaction recursion'));
    });

    test('client id duplicate change', () {
      testClientIdDuplicateChange(t.TestCase('doc', 'client id duplicate change'));
    });

    test('get type empty id', () {
      testGetTypeEmptyId(t.TestCase('doc', 'get type empty id'));
    });

    test('toJSON', () {
      testToJSON(t.TestCase('doc', 'toJSON'));
    });

    test('subdoc', () {
      testSubdoc(t.TestCase('doc', 'subdoc'));
    });

    test('subdoc load edge cases', () {
      testSubdocLoadEdgeCases(t.TestCase('doc', 'subdoc load edge cases'));
    });

    test('subdoc load edge cases autoload', () {
      testSubdocLoadEdgeCasesAutoload(t.TestCase('doc', 'subdoc load edge cases autoload'));
    });

    test('subdocs undo', () {
      testSubdocsUndo(t.TestCase('doc', 'subdocs undo'));
    });

    test('load docs event', () async {
      await testLoadDocsEvent(t.TestCase('doc', 'load docs event'));
    });

    test('sync docs event', () async {
      await testSyncDocsEvent(t.TestCase('doc', 'sync docs event'));
    });
  });
}

/**
 * @param {t.TestCase} _tc
 */
void testAfterTransactionRecursion(t.TestCase _tc) {
  final ydoc = y.Doc();
  final yxml = ydoc.getXmlFragment('');
  ydoc.on('afterTransaction', (params) {
    final tr = params[0] as Transaction;
    if (tr.origin == 'test') {
      yxml.toJSON();
    }
  });
  ydoc.transact((Transaction _tr) {
    for (var i = 0; i < 15000; i++) {
      yxml.push([y.YXmlText('a')]);
    }
  }, 'test');
}

/**
 * @param {t.TestCase} _tc
 */
void testOriginInTransaction(t.TestCase _tc) {
  final doc = y.Doc();
  final ytext = doc.getText();
  /**
   * @type {Array<string>}
   */
  final origins = [];
  doc.on('afterTransaction', (params) {
    final tr = params[0] as Transaction;
    origins.add(tr.origin);
    if (origins.length <= 1) {
      ytext.toDelta(y.snapshot(doc)); // adding a snapshot forces toDelta to create a cleanup transaction
      doc.transact((_) {
        ytext.insert(0, 'a');
      }, 'nested');
    }
  });
  doc.transact((_) {
    ytext.insert(0, '0');
  }, 'first');
  expect(origins, equals(['first', 'cleanup', 'nested']));
}

/**
 * Client id should be changed when an instance receives updates from another client using the same client id.
 *
 * @param {t.TestCase} _tc
 */
void testClientIdDuplicateChange(t.TestCase _tc) {
  final doc1 = y.Doc();
  doc1.clientID = 0;
  final doc2 = y.Doc();
  doc2.clientID = 0;
  expect(doc2.clientID, doc1.clientID);
  doc1.getArray('a').insert(0, [1, 2]);
  y.applyUpdate(doc2, y.encodeStateAsUpdate(doc1));
  expect(doc2.clientID != doc1.clientID, true);
}

/**
 * @param {t.TestCase} _tc
 */
void testGetTypeEmptyId(t.TestCase _tc) {
  final doc1 = y.Doc();
  doc1.getText('').insert(0, 'h');
  doc1.getText().insert(1, 'i');
  final doc2 = y.Doc();
  y.applyUpdate(doc2, y.encodeStateAsUpdate(doc1));
  expect(doc2.getText().toString(), 'hi');
  expect(doc2.getText('').toString(), 'hi');
}

/**
 * @param {t.TestCase} _tc
 */
void testToJSON(t.TestCase _tc) {
  final doc = y.Doc();
  expect(doc.toJSON(), equals({}), reason: 'doc.toJSON yields empty object');

  final arr = doc.getArray('array');
  arr.push(['test1']);

  final map = doc.getMap('map');
  map.set('k1', 'v1');
  final map2 = y.YMap();
  map.set('k2', map2);
  map2.set('m2k1', 'm2v1');

  expect(doc.toJSON(), equals({
    'array': ['test1'],
    'map': {
      'k1': 'v1',
      'k2': {
        'm2k1': 'm2v1'
      }
    }
  }), reason: 'doc.toJSON has array and recursive map');
}

/**
 * @param {t.TestCase} _tc
 */
void testSubdoc(t.TestCase _tc) {
  final doc = y.Doc();
  doc.load(); // doesn't do anything
  {
    /**
     * @type {Array<any>|null}
     */
    var event;
    doc.on('subdocs', (params) {
      final subdocs = fromSubdocsEventData(params);
      event = [subdocs.added.map((x) => x.guid).toList(),
        subdocs.removed.map((x) => x.guid).toList(),
        subdocs.loaded.map((x) => x.guid).toList()];
    });
    final subdocs = doc.getMap('mysubdocs');
    final docA = y.Doc(guid: 'a');
    docA.load();
    subdocs.set('a', docA);
    expect(event, equals([['a'], [], ['a']]));

    event = null;
    (subdocs.get('a') as y.Doc).load();
    assert(event == null);

    event = null;
    (subdocs.get('a') as y.Doc).destroy();
    expect(event, equals([['a'], ['a'], []]));
    (subdocs.get('a') as y.Doc).load();
    expect(event, equals([[], [], ['a']]));

    subdocs.set('b', y.Doc(guid: 'a', shouldLoad: false));
    expect(event, equals([['a'], [], []]));
    (subdocs.get('b') as y.Doc).load();
    expect(event, equals([[], [], ['a']]));

    final docC = y.Doc(guid: 'c' );
    docC.load();
    subdocs.set('c', docC);
    expect(event, equals([['c'], [], ['c']]));

    expect(doc.getSubdocGuids(), equals(['a', 'c']));
  }

  final doc2 = y.Doc();
  {
    expect(doc2.getSubdocs(), equals([]));
    /**
     * @type {Array<any>|null}
     */
    var event;
    doc2.on('subdocs', (args) {
      final subdocs = fromSubdocsEventData(args);
      event = [
        subdocs.added.map((d) => d.guid).toList(), 
        subdocs.removed.map((d) => d.guid).toList(), 
        subdocs.loaded.map((d) => d.guid).toList()];
    });
    y.applyUpdate(doc2, y.encodeStateAsUpdate(doc));
    expect(event, equals([['a', 'a', 'c'], [], []]));

    doc2.getMap('mysubdocs').get('a').load();
    expect(event, equals([[], [], ['a']]));

    expect(doc2.getSubdocGuids(), equals(['a', 'c']));

    doc2.getMap('mysubdocs').delete('a');
    expect(event, equals([[], ['a'], []]));
    expect(doc2.getSubdocGuids(), equals(['a', 'c']));
  }
}

/**
 * @param {t.TestCase} _tc
 */
void testSubdocLoadEdgeCases(t.TestCase _tc) {
  final ydoc = y.Doc();
  final yarray = ydoc.getArray();
  final subdoc1 = y.Doc();
  /**
   * @type {any}
   */
  ({Set<y.Doc> loaded, Set<y.Doc> added, Set<y.Doc> removed})? lastEvent;
  ydoc.on('subdocs', (params) {
    lastEvent = fromSubdocsEventData(params);
  });
  yarray.insert(0, [subdoc1]);
  expect(subdoc1.shouldLoad, true);
  expect(subdoc1.autoLoad, false);
  expect(lastEvent != null && lastEvent!.loaded.contains(subdoc1), true);
  expect(lastEvent != null && lastEvent!.added.contains(subdoc1), true);
  // destroy and check whether lastEvent adds it again to added (it shouldn't)
  subdoc1.destroy();
  final subdoc2 = yarray.get(0) as y.Doc;
  expect(subdoc1 != subdoc2, true);
  expect(lastEvent != null && lastEvent!.added.contains(subdoc2), true);
  expect(lastEvent != null && !lastEvent!.loaded.contains(subdoc2), true);
  // load
  subdoc2.load();
  expect(lastEvent != null && !lastEvent!.added.contains(subdoc2), true);
  expect(lastEvent != null && lastEvent!.loaded.contains(subdoc2), true);
  // apply from remote
  final ydoc2 = y.Doc();
  ydoc2.on('subdocs', (params) {
    lastEvent = fromSubdocsEventData(params);
  });
  y.applyUpdate(ydoc2, y.encodeStateAsUpdate(ydoc));
  final subdoc3 = ydoc2.getArray().get(0) as y.Doc;
  expect(subdoc3.shouldLoad, false);
  expect(subdoc3.autoLoad, false);
  expect(lastEvent != null && lastEvent!.added.contains(subdoc3), true);
  expect(lastEvent != null && !lastEvent!.loaded.contains(subdoc3), true);
  // load
  subdoc3.load();
  expect(subdoc3.shouldLoad, true);
  expect(lastEvent != null && !lastEvent!.added.contains(subdoc3), true);
  expect(lastEvent != null && lastEvent!.loaded.contains(subdoc3), true);
}

/**
 * @param {t.TestCase} _tc
 */
void testSubdocLoadEdgeCasesAutoload(t.TestCase _tc) {
  final ydoc = y.Doc();
  final yarray = ydoc.getArray();
  final subdoc1 = y.Doc(autoLoad: true);
  /**
   * @type {any}
   */
  ({Set<y.Doc> loaded, Set<y.Doc> added, Set<y.Doc> removed})? lastEvent;
  ydoc.on('subdocs', (params) {
    lastEvent = fromSubdocsEventData(params);
  });
  yarray.insert(0, [subdoc1]);
  expect(subdoc1.shouldLoad, true);
  expect(subdoc1.autoLoad, true);
  expect(lastEvent != null && lastEvent!.loaded.contains(subdoc1), true);
  expect(lastEvent != null && lastEvent!.added.contains(subdoc1), true);
  // destroy and check whether lastEvent adds it again to added (it shouldn't)
  subdoc1.destroy();
  final subdoc2 = yarray.get(0) as y.Doc;
  expect(subdoc1 != subdoc2, true);
  expect(lastEvent != null && lastEvent!.added.contains(subdoc2), true);
  expect(lastEvent != null && !lastEvent!.loaded.contains(subdoc2), true);
  // load
  subdoc2.load();
  expect(lastEvent != null && !lastEvent!.added.contains(subdoc2), true);
  expect(lastEvent != null && lastEvent!.loaded.contains(subdoc2), true);
  // apply from remote
  final ydoc2 = y.Doc();
  ydoc2.on('subdocs', (params) {
    lastEvent = fromSubdocsEventData(params);
  });
  y.applyUpdate(ydoc2, y.encodeStateAsUpdate(ydoc));
  final subdoc3 = ydoc2.getArray().get(0);
  expect(subdoc1.shouldLoad, true);
  expect(subdoc1.autoLoad, true);
  expect(lastEvent != null && lastEvent!.added.contains(subdoc3), true);
  expect(lastEvent != null && lastEvent!.loaded.contains(subdoc3), true);
}

/**
 * @param {t.TestCase} _tc
 */
void testSubdocsUndo(t.TestCase _tc) {
  final ydoc = y.Doc();
  final elems = ydoc.getXmlFragment();
  final undoManager = y.UndoManager(elems);
  final subdoc = y.Doc();
  // @ts-ignore
  elems.insert(0, [subdoc]);
  undoManager.undo();
  undoManager.redo();
  expect(elems.length, 1);
}

/**
 * @param {t.TestCase} _tc
 */
Future testLoadDocsEvent(t.TestCase _tc) async {
  final ydoc = y.Doc();
  expect(ydoc.isLoaded, false);
  var loadedEvent = false;
  ydoc.on('load', (_) {
    loadedEvent = true;
  });
  ydoc.emit('load', [ydoc]);
  await ydoc.whenLoaded;
  expect(loadedEvent, true);
  expect(ydoc.isLoaded, true);
}

/**
 * @param {t.TestCase} _tc
 */
Future testSyncDocsEvent(t.TestCase _tc) async {
  final ydoc = y.Doc();
  expect(ydoc.isLoaded, false);
  expect(ydoc.isSynced, false);
  var loadedEvent = false;
  ydoc.once('load', (_) {
    loadedEvent = true;
  });
  var syncedEvent = false;
  ydoc.once('sync', /** @param {any} isSynced */ (List args) {
    final isSynced = args.firstOrNull;
    syncedEvent = true;
    expect(isSynced, true);
  });
  ydoc.emit('sync', [true, ydoc]);
  await ydoc.whenLoaded;
  final oldWhenSynced = ydoc.whenSynced;
  await ydoc.whenSynced;
  expect(loadedEvent, true);
  expect(syncedEvent, true);
  expect(ydoc.isLoaded, true);
  expect(ydoc.isSynced, true);
  var loadedEvent2 = false;
  ydoc.on('load', (_) {
    loadedEvent2 = true;
  });
  var syncedEvent2 = false;
  ydoc.on('sync', (List args) {
    final isSynced = args.firstOrNull;
    syncedEvent2 = true;
    expect(isSynced, false);
  });
  ydoc.emit('sync', [false, ydoc]);
  expect(!loadedEvent2, true);
  expect(syncedEvent2, true);
  expect(ydoc.isLoaded, true);
  expect(!ydoc.isSynced, true);
  expect(ydoc.whenSynced != oldWhenSynced, true);
}