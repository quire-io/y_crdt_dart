// import { init } from './testHelper.js' // eslint-disable-line

// import * as Y from '../src/index.js'
// import * as t from 'lib0/testing'

import 'dart:typed_data';

import "package:test/test.dart";

import "package:y_crdt/src/lib0/testing.dart" as t;
import "package:y_crdt/src/types/y_map.dart";
import "package:y_crdt/src/types/y_xml_element.dart";
import "package:y_crdt/src/utils/doc.dart";
import "package:y_crdt/src/utils/undo_manager.dart";
import "package:y_crdt/src/types/y_text.dart";
import "package:y_crdt/src/types/y_array.dart";

import 'package:y_crdt/y_crdt.dart' as y;

import "test_helper.dart";


void main() {
  group('undo redo', () {
    test('inconsistent format', testInconsistentFormat);
  
    //TODO: YArray test case
    // test('infinite capture timeout', () {
    //   testInfiniteCaptureTimeout(t.TestCase('undo redo', 'infinite capture timeout'));
    // });

    test('undo text', () {
      testUndoText(t.TestCase('undo redo', 'undo text'));
    });

    test('empty type scope', () {
      testEmptyTypeScope(t.TestCase('undo redo', 'empty type scope'));
    });

    test('reject update example', () {
      testRejectUpdateExample(t.TestCase('undo redo', 'reject update example'));
    });

    test('global scope', () {
      testGlobalScope(t.TestCase('undo redo', 'global scope'));
    });

    test('double undo', () {
      testDoubleUndo(t.TestCase('undo redo', 'double undo'));
    });

    test('undo map', () {
      testUndoMap(t.TestCase('undo redo', 'undo map'));
    });

    test('undo array', () {
      testUndoArray(t.TestCase('undo redo', 'undo array'));
    });

    //TODO: upgrade YXmlElement
    // test('undo xml', () {
    //   testUndoXml(t.TestCase('undo redo', 'undo xml'));
    // });

    test('undo events', () {
      testUndoEvents(t.TestCase('undo redo', 'undo events'));
    });

    test('track class', () {
      testTrackClass(t.TestCase('undo redo', 'track class'));
    });

    test('type scope', () {
      testTypeScope(t.TestCase('undo redo', 'type scope'));
    });

    test('undo in embed', () {
      testUndoInEmbed(t.TestCase('undo redo', 'undo in embed'));
    });

    test('undo delete filter', () {
      testUndoDeleteFilter(t.TestCase('undo redo', 'undo delete filter'));
    });

    test('undo until change performed', () {
      testUndoUntilChangePerformed(t.TestCase('undo redo', 'undo until change performed'));
    });

    test('undo nested undo issue', () {
      testUndoNestedUndoIssue(t.TestCase('undo redo', 'undo nested undo issue'));
    });

    test('consecutive redo bug', () {
      testConsecutiveRedoBug(t.TestCase('undo redo', 'consecutive redo bug'));
    });

    test('undo xml bug', () {
      testUndoXmlBug(t.TestCase('undo redo', 'undo xml bug'));
    });

    test('undo block bug', () {
      testUndoBlockBug(t.TestCase('undo redo', 'undo block bug'));
    });

    test('undo delete text format', () {
      testUndoDeleteTextFormat(t.TestCase('undo redo', 'undo delete text format'));
    });

    test('behavior of ignoreRemoteMapChanges property', () {
      testBehaviorOfIgnoreremotemapchangesProperty(t.TestCase('undo redo', 'behavior of ignoreRemoteMapChanges property'));
    });

    test('special deletion case', () {
      testSpecialDeletionCase(t.TestCase('undo redo', 'special deletion case'));
    });

    test('undo delete in map', () {
      testUndoDeleteInMap(t.TestCase('undo redo', 'undo delete in map'));
    });

    test('undo doing stack item', () async {
      await testUndoDoingStackItem(t.TestCase('undo redo', 'undo doing stack item'));
    });
  });

}

void testInconsistentFormat() {
  /**
   * @param {Y.Doc} ydoc
   */
  void testYjsMerge(y.Doc ydoc) {
    final content = /** @type {Y.XmlText} */ (ydoc.get('text', y.YXmlText.new));
    content.format(0, 6, { 'bold': null });
    content.format(6, 4, { 'type': 'text' });
    expect(content.toDelta(), equals([
      {
        'attributes': { 'type': 'text' },
        'insert': 'Merge Test'
      },
      {
        'attributes': { 'type': 'text', 'italic': true },
        'insert': ' After'
      }
    ]));
  }
  y.Doc initializeYDoc() {
    final yDoc = y.Doc(gc: false);

    final content = /** @type {Y.XmlText} */ (yDoc.get('text', y.YXmlText.new));
    content.insert(0, ' After', { 'type': 'text', 'italic': true });
    content.insert(0, 'Test', { 'type': 'text' });
    content.insert(0, 'Merge ', { 'type': 'text', 'bold': true });
    return yDoc;
  }
  {
    final yDoc = initializeYDoc();
    testYjsMerge(yDoc);
  }
  {
    final initialYDoc = initializeYDoc();
    final yDoc = y.Doc(gc: false);
    y.applyUpdate(yDoc, y.encodeStateAsUpdate(initialYDoc));
    testYjsMerge(yDoc);
  }
}

/**
 * @param {t.TestCase} tc
 */
void testInfiniteCaptureTimeout(t.TestCase tc) {
  final results = init(tc, users: 3 ),
    array0 = results['array0'] as YArray;
  final undoManager = y.UndoManager(array0, captureTimeout: double.maxFinite.toInt());
  array0.push([1, 2, 3]);
  undoManager.stopCapturing();
  array0.push([4, 5, 6]);
  undoManager.undo();
  expect(array0.toArray(), equals([1, 2, 3]));
}

/**
 * @param {t.TestCase} tc
 */
void testUndoText(t.TestCase tc) {
  final results = init(tc, users: 3),
    testConnector = results['testConnector'] as TestConnector,
    text0 = results['text0'] as YText,
    text1 = results['text1'] as YText;
  final undoManager = y.UndoManager(text0);

  // items that are added & deleted in the same transaction won't be undo
  text0.insert(0, 'test');
  text0.delete(0, 4);
  undoManager.undo();
  expect(text0.toString(), '');

  // follow redone items
  text0.insert(0, 'a');
  undoManager.stopCapturing();
  text0.delete(0, 1);
  undoManager.stopCapturing();
  undoManager.undo();
  
  expect(text0.toString(), 'a');
  undoManager.undo();
  expect(text0.toString(), '');

  text0.insert(0, 'abc');
  text1.insert(0, 'xyz');
  testConnector.syncAll();
  undoManager.undo();
  expect(text0.toString(), 'xyz');
  undoManager.redo();
  expect(text0.toString(), 'abcxyz');
  testConnector.syncAll();
  text1.delete(0, 1);
  testConnector.syncAll();
  undoManager.undo();
  expect(text0.toString(), 'xyz');
  undoManager.redo();
  expect(text0.toString(), 'bcxyz');
  // test marks
  text0.format(1, 3, { 'bold': true });
  expect(text0.toDelta(), equals([
    { 'insert': 'b' }, 
    { 'insert': 'cxy', 'attributes': { 'bold': true } }, 
    { 'insert': 'z' }]));
  undoManager.undo();
  expect(text0.toDelta(), equals([{ 'insert': 'bcxyz' }]));
  undoManager.redo();
  expect(text0.toDelta(), equals([
    { 'insert': 'b' }, 
    { 'insert': 'cxy', 'attributes': { 'bold': true } }, 
    { 'insert': 'z' }]));
}

/**
 * Test case to fix #241
 * @param {t.TestCase} _tc
 */
void testEmptyTypeScope(t.TestCase _tc) {
  final ydoc = y.Doc();
  final um = y.UndoManager([], doc: ydoc);
  final yarray = ydoc.getArray();
  um.addToScope(yarray);
  yarray.insert(0, [1]);
  um.undo();
  expect(yarray.length, 0);
}

/**
 * @param {t.TestCase} _tc
 */
void testRejectUpdateExample(t.TestCase _tc) {
  final tmpydoc1 = y.Doc();
  tmpydoc1.getArray('restricted').insert(0, [1]);
  tmpydoc1.getArray('public').insert(0, [1]);
  final update1 = y.encodeStateAsUpdate(tmpydoc1);
  final tmpydoc2 = y.Doc();
  tmpydoc2.getArray('public').insert(0, [2]);
  final update2 = y.encodeStateAsUpdate(tmpydoc2);

  final ydoc = y.Doc();
  final restrictedType = ydoc.getArray('restricted');

  /**
   * Assume this function handles incoming updates via a communication channel like websockets.
   * Changes to the `ydoc.getMap('restricted')` type should be rejected.
   *
   * - set up undo manager on the restricted types
   * - cache pending* updates from the Ydoc to avoid certain attacks
   * - apply received update and check whether the restricted type (or any of its children) has been changed.
   * - catch errors that might try to circumvent the restrictions
   * - undo changes on restricted types
   * - reapply pending* updates
   *
   * @param {Uint8Array} update
   */
  void updateHandler(Uint8List update) {
    // don't handle changes of the local undo manager, which is used to undo invalid changes
    final um = y.UndoManager(restrictedType, trackedOrigins: {'remote change'});
    final beforePendingDs = ydoc.store.pendingDs;
    final beforePendingStructs = ydoc.store.pendingStructs?.update;
    try {
      y.applyUpdate(ydoc, update, 'remote change');
    } finally {
      while (um.undoStack.isNotEmpty) {
        um.undo();
      }
      um.destroy();
      ydoc.store.pendingDs = beforePendingDs;
      ydoc.store.pendingStructs = null;
      if (beforePendingStructs != null) {
        y.applyUpdateV2(ydoc, beforePendingStructs);
      }
    }
  }
  updateHandler(update1);
  updateHandler(update2);
  expect(restrictedType.length, 0);
  expect(ydoc.getArray('public').length, 2);
}

/**
 * Test case to fix #241
 * @param {t.TestCase} _tc
 */
void testGlobalScope(t.TestCase _tc) {
  final ydoc = y.Doc();
  final um = y.UndoManager(ydoc);
  final yarray = ydoc.getArray();
  yarray.insert(0, [1]);
  um.undo();
  expect(yarray.length, 0);
}

/**
 * Test case to fix #241
 * @param {t.TestCase} _tc
 */
void testDoubleUndo(t.TestCase _tc) {
  final doc = y.Doc();
  final text = doc.getText();
  text.insert(0, '1221');

  final manager = y.UndoManager(text);

  text.insert(2, '3');
  text.insert(3, '3');

  manager.undo();
  manager.undo();

  text.insert(2, '3');

  expect(text.toString(), '12321');
}

/**
 * @param {t.TestCase} tc
 */
void testUndoMap(t.TestCase tc) {
  final results = init(tc, users: 2),
    testConnector = results['testConnector'] as TestConnector,
    map0 = results['map0'] as YMap,
    map1 = results['map1'] as YMap;

  map0.set('a', 0);
  final undoManager = y.UndoManager(map0);
  map0.set('a', 1);
  undoManager.undo();
  expect(map0.get('a'), 0);
  undoManager.redo();
  expect(map0.get('a'), 1);
  // testing sub-types and if it can restore a whole type
  final subType = y.YMap();
  map0.set('a', subType);
  subType.set('x', 42);
  expect(map0.toJSON(), /** @type {any} */ equals({ 'a': { 'x': 42 } }));
  undoManager.undo();
  expect(map0.get('a'), 1);
  undoManager.redo();
  expect(map0.toJSON(), /** @type {any} */ equals({ 'a': { 'x': 42 } }));
  testConnector.syncAll();
  // if content is overwritten by another user, undo operations should be skipped
  map1.set('a', 44);
  testConnector.syncAll();
  undoManager.undo();
  expect(map0.get('a'), 44);
  undoManager.redo();
  expect(map0.get('a'), 44);

  // test setting value multiple times
  map0.set('b', 'initial');
  undoManager.stopCapturing();
  map0.set('b', 'val1');
  map0.set('b', 'val2');
  undoManager.stopCapturing();
  undoManager.undo();
  expect(map0.get('b'), 'initial');
}

/**
 * @param {t.TestCase} tc
 */
void testUndoArray(t.TestCase tc) {
  final results = init(tc, users: 3),
    testConnector = results['testConnector'] as TestConnector,
    array0 = results['array0'] as YArray,
    array1 = results['array1'] as YArray;
  final undoManager = y.UndoManager(array0);
  array0.insert(0, [1, 2, 3]);
  array1.insert(0, [4, 5, 6]);
  testConnector.syncAll();
  expect(array0.toArray(), equals([1, 2, 3, 4, 5, 6]));
  undoManager.undo();
  expect(array0.toArray(), equals([4, 5, 6]));
  undoManager.redo();
  expect(array0.toArray(), equals([1, 2, 3, 4, 5, 6]));
  testConnector.syncAll();
  array1.delete(0, 1); // user1 deletes [1]
  testConnector.syncAll();
  undoManager.undo();
  expect(array0.toArray(), equals([4, 5, 6]));
  undoManager.redo();
  expect(array0.toArray(), equals([2, 3, 4, 5, 6]));
  array0.delete(0, 5);
  // test nested structure
  final ymap = y.YMap();
  array0.insert(0, [ymap]);
  expect(array0.toJSON(), equals([{}]));
  undoManager.stopCapturing();
  ymap.set('a', 1);
  expect(array0.toJSON(), equals([{ 'a': 1 }]));
  undoManager.undo();
  expect(array0.toJSON(), equals([{}]));
  undoManager.undo();
  expect(array0.toJSON(), equals([2, 3, 4, 5, 6]));
  undoManager.redo();
  expect(array0.toJSON(), equals([{}]));
  undoManager.redo();
  expect(array0.toJSON(), equals([{ 'a': 1 }]));
  testConnector.syncAll();
  array1.get(0).set('b', 2);
  testConnector.syncAll();
  expect(array0.toJSON(), equals([{ 'a': 1, 'b': 2 }]));
  undoManager.undo();
  expect(array0.toJSON(), equals([{ 'b': 2 }]));
  undoManager.undo();
  expect(array0.toJSON(), equals([2, 3, 4, 5, 6]));
  undoManager.redo();
  expect(array0.toJSON(), equals([{ 'b': 2 }]));
  undoManager.redo();
  expect(array0.toJSON(), equals([{ 'a': 1, 'b': 2 }]));
}

/**
 * @param {t.TestCase} tc
 */
void testUndoXml(t.TestCase tc) {
  final results = init(tc, users: 3 ),
    xml0 = results['xml0'] as YXmlElement;
  final undoManager = y.UndoManager(xml0);
  final child = y.YXmlElement('p');
  xml0.insert(0, [child]);
  final textchild = y.YXmlText('content');
  child.insert(0, [textchild]);
  expect(xml0.toString(), '<undefined><p>content</p></undefined>');
  // format textchild and revert that change
  undoManager.stopCapturing();
  textchild.format(3, 4, { 'bold': {} });
  expect(xml0.toString(), '<undefined><p>con<bold>tent</bold></p></undefined>');
  undoManager.undo();
  expect(xml0.toString(), '<undefined><p>content</p></undefined>');
  undoManager.redo();
  expect(xml0.toString(), '<undefined><p>con<bold>tent</bold></p></undefined>');
  xml0.delete(0, 1);
  expect(xml0.toString(), '<undefined></undefined>');
  undoManager.undo();
  expect(xml0.toString(), '<undefined><p>con<bold>tent</bold></p></undefined>');
}

/**
 * @param {t.TestCase} tc
 */
void testUndoEvents(t.TestCase tc) {
  final results = init(tc, users: 3 ),
    text0 = results['text0'] as YText;
  final undoManager = y.UndoManager(text0);
  var counter = 0;
  var receivedMetadata = -1;
  undoManager.on('stack-item-added', /** @param {any} event */ (params) {
    final event = fromUndoEventData(params);
    expect(event.type, isNotNull);
    expect(event.changedParentTypes != null && event.changedParentTypes!.containsKey(text0), isTrue);
    event.stackItem.meta.set('test', counter++);
  });
  undoManager.on('stack-item-popped', /** @param {any} event */ (params) {
    final event = fromUndoEventData(params);
    expect(event.type, isNotNull);
    expect(event.changedParentTypes != null && event.changedParentTypes!.containsKey(text0), isTrue);
    receivedMetadata = event.stackItem.meta.get('test');
  });
  text0.insert(0, 'abc');
  undoManager.undo();
  expect(receivedMetadata, 0);
  undoManager.redo();
  expect(receivedMetadata, 1);
}

/**
 * @param {t.TestCase} tc
 */
void testTrackClass(t.TestCase tc) {
  final results = init(tc, users: 3 ),
    users = results['users'] as List,
    text0 = results['text0'] as YText;
  // only track origins that are numbers
  
  //const undoManager = new Y.UndoManager(text0, { trackedOrigins: new Set([Number]) })
  //for this.trackedOrigins.contains(transaction.origin.runtimeType)
  final undoManager = y.UndoManager(text0, trackedOrigins: {0.runtimeType});
  (users[0] as TestYInstance).transact((_) {
    text0.insert(0, 'abc');
  }, 42);
  expect(text0.toString(), 'abc');
  undoManager.undo();
  expect(text0.toString(), '');
}

/**
 * @param {t.TestCase} tc
 */
void testTypeScope(t.TestCase tc) {
  final results = init(tc, users: 3 ),
    array0 = results['array0'] as YArray;
  // only track origins that are numbers
  final text0 = y.YText();
  final text1 = y.YText();
  array0.insert(0, [text0, text1]);
  final undoManager = y.UndoManager(text0);
  final undoManagerBoth = y.UndoManager([text0, text1]);
  text1.insert(0, 'abc');
  expect(undoManager.undoStack.length, 0);
  expect(undoManagerBoth.undoStack.length, 1);
  expect(text1.toString(), 'abc');
  undoManager.undo();
  expect(text1.toString(), 'abc');
  undoManagerBoth.undo();
  expect(text1.toString(), '');
}

/**
 * @param {t.TestCase} tc
 */
void testUndoInEmbed(t.TestCase tc) {
  final results = init(tc, users: 3 ),
    text0 = results['text0'] as YText;

  final undoManager = y.UndoManager(text0);
  final nestedText = y.YText('initial text');
  undoManager.stopCapturing();
  text0.insertEmbed(0, nestedText, { 'bold': true });
  expect(nestedText.toString(), 'initial text');
  undoManager.stopCapturing();
  nestedText.delete(0, nestedText.length);
  nestedText.insert(0, 'other text');
  expect(nestedText.toString(), 'other text');
  undoManager.undo();
  expect(nestedText.toString(), 'initial text');
  undoManager.undo();
  expect(text0.length, 0);
}

/**
 * @param {t.TestCase} tc
 */
void testUndoDeleteFilter(t.TestCase tc) {
  /**
   * @type {Y.Array<any>}
   */
  final results = init(tc, users: 3 ),
    array0 = results['array0'] as YArray;
  final undoManager = y.UndoManager(array0, 
    deleteFilter: (item) => !(item is y.Item) || (item.content is y.ContentType 
      && (item.content as y.ContentType).type.innerMap.isEmpty));
  final map0 = y.YMap();
  map0.set('hi', 1);
  final map1 = y.YMap();
  array0.insert(0, [map0, map1]);
  undoManager.undo();
  expect(array0.length, 1);
  array0.get(0);
  expect((array0.get(0) as y.YMap).keys().length, 1);
}

/**
 * This issue has been reported in https://discuss.yjs.dev/t/undomanager-with-external-updates/454/6
 * @param {t.TestCase} _tc
 */
void testUndoUntilChangePerformed(t.TestCase _tc) {
  final doc = y.Doc();
  final doc2 = y.Doc();
  doc.on('update', (args) => y.applyUpdate(doc2, args[0] as Uint8List));
  doc2.on('update', (args) => y.applyUpdate(doc, args[0] as Uint8List));

  final yArray = doc.getArray('array');
  final yArray2 = doc2.getArray('array');
  final yMap = y.YMap();
  yMap.set('hello', 'world');
  yArray.push([yMap]);
  final yMap2 = y.YMap();
  yMap2.set('key', 'value');
  yArray.push([yMap2]);

  final undoManager = y.UndoManager([yArray], trackedOrigins: {doc.clientID});
  final undoManager2 = y.UndoManager([doc2.get('array')], trackedOrigins: {doc2.clientID});

  y.transact(doc, (_) => yMap2.set('key', 'value modified'), doc.clientID);
  undoManager.stopCapturing();
  y.transact(doc, (_) => yMap.set('hello', 'world modified'), doc.clientID);
  y.transact(doc2, (_) => yArray2.delete(0), doc2.clientID);
  undoManager2.undo();
  undoManager.undo();
  expect(yMap2.get('key'), 'value');
}

/**
 * This issue has been reported in https://github.com/yjs/yjs/issues/317
 * @param {t.TestCase} _tc
 */
void testUndoNestedUndoIssue(t.TestCase _tc) {
  final doc = y.Doc(gc: false);
  final design = doc.getMap();
  final undoManager = y.UndoManager(design, captureTimeout: 0);

  /**
   * @type {Y.Map<any>}
   */
  final text = y.YMap();

  final blocks1 = y.YArray();
  final blocks1block = y.YMap();

  doc.transact((_) {
    blocks1block.set('text', 'Type Something');
    blocks1.push([blocks1block]);
    text.set('blocks', blocks1block);
    design.set('text', text);
  });

  final blocks2 = y.YArray();
  final blocks2block = y.YMap();
  doc.transact((_) {
    blocks2block.set('text', 'Something');
    blocks2.push([blocks2block]);
    text.set('blocks', blocks2block);
  });

  final blocks3 = y.YArray();
  final blocks3block = y.YMap();
  doc.transact((_) {
    blocks3block.set('text', 'Something Else');
    blocks3.push([blocks3block]);
    text.set('blocks', blocks3block);
  });

  expect(design.toJSON(), equals({ 'text': { 'blocks': { 'text': 'Something Else' } } }));
  undoManager.undo();
  expect(design.toJSON(), equals({ 'text': { 'blocks': { 'text': 'Something' } } }));
  undoManager.undo();
  expect(design.toJSON(), equals({ 'text': { 'blocks': { 'text': 'Type Something' } } }));
  undoManager.undo();
  expect(design.toJSON(), equals({ }));
  undoManager.redo();
  expect(design.toJSON(), equals({ 'text': { 'blocks': { 'text': 'Type Something' } } }));
  undoManager.redo();
  expect(design.toJSON(), equals({ 'text': { 'blocks': { 'text': 'Something' } } }))  ;
  undoManager.redo();
  expect(design.toJSON(), equals({ 'text': { 'blocks': { 'text': 'Something Else' } } }));
}

/**
 * This issue has been reported in https://github.com/yjs/yjs/issues/355
 *
 * @param {t.TestCase} _tc
 */
void testConsecutiveRedoBug(t.TestCase _tc) {
  final doc = y.Doc();
  final yRoot = doc.getMap();
  final undoMgr = y.UndoManager(yRoot);

  var yPoint = y.YMap();
  yPoint.set('x', 0);
  yPoint.set('y', 0);
  yRoot.set('a', yPoint);
  undoMgr.stopCapturing();

  yPoint.set('x', 100);
  yPoint.set('y', 100);
  undoMgr.stopCapturing();

  yPoint.set('x', 200);
  yPoint.set('y', 200);
  undoMgr.stopCapturing();

  yPoint.set('x', 300);
  yPoint.set('y', 300);
  undoMgr.stopCapturing();

  expect(yPoint.toJSON(), equals({ 'x': 300, 'y': 300 }));

  undoMgr.undo(); // x=200, y=200
  expect(yPoint.toJSON(), equals({ 'x': 200, 'y': 200 }));
  undoMgr.undo(); // x=100, y=100
  expect(yPoint.toJSON(), equals({ 'x': 100, 'y': 100 }));
  undoMgr.undo(); // x=0, y=0
  expect(yPoint.toJSON(), equals({ 'x': 0, 'y': 0 }));
  undoMgr.undo(); // nil
  expect(yRoot.get('a'), isNull);

  undoMgr.redo(); // x=0, y=0
  yPoint = yRoot.get('a');

  expect(yPoint.toJSON(), equals({ 'x': 0, 'y': 0 }));
  undoMgr.redo(); // x=100, y=100
  expect(yPoint.toJSON(), equals({ 'x': 100, 'y': 100 }));
  undoMgr.redo(); // x=200, y=200
  expect(yPoint.toJSON(), equals({ 'x': 200, 'y': 200 }));
  undoMgr.redo(); // expected x=300, y=300, actually nil
  expect(yPoint.toJSON(), equals({ 'x': 300, 'y': 300 }));
}

/**
 * This issue has been reported in https://github.com/yjs/yjs/issues/304
 *
 * @param {t.TestCase} _tc
 */
void testUndoXmlBug(t.TestCase _tc) {
  final origin = 'origin';
  final doc = y.Doc();
  final fragment = doc.getXmlFragment('t');
  final undoManager = y.UndoManager(fragment,
    captureTimeout: 0,
    trackedOrigins: {origin});

  // create element
  doc.transact((_) {
    final e = y.YXmlElement('test-node');
    e.setAttribute('a', '100');
    e.setAttribute('b', '0');
    fragment.insert(fragment.length, [e]);
  }, origin);

  // change one attribute
  doc.transact((_) {
    final e = fragment.get(0) as y.YXmlElement;
    e.setAttribute('a', '200');
  }, origin);

  // change both attributes
  doc.transact((_) {
    final e = fragment.get(0) as y.YXmlElement;
    e.setAttribute('a', '180');
    e.setAttribute('b', '50');
  }, origin);

  undoManager.undo();
  undoManager.undo();
  undoManager.undo();

  undoManager.redo();
  undoManager.redo();
  undoManager.redo();
  expect(fragment.toString(), '<test-node a="180" b="50"></test-node>');
}

/**
 * This issue has been reported in https://github.com/yjs/yjs/issues/343
 *
 * @param {t.TestCase} _tc
 */
void testUndoBlockBug(t.TestCase _tc) {
  final doc = y.Doc(gc: false);
  final design = doc.getMap();

  final undoManager = y.UndoManager(design, captureTimeout: 0);

  final text = y.YMap();

  final blocks1 = y.YArray();
  final blocks1block = y.YMap();
  doc.transact((_) {
    blocks1block.set('text', '1');
    blocks1.push([blocks1block]);

    text.set('blocks', blocks1block);
    design.set('text', text);
  });

  final blocks2 = y.YArray();
  final blocks2block = y.YMap();
  doc.transact((_) {
    blocks2block.set('text', '2');
    blocks2.push([blocks2block]);
    text.set('blocks', blocks2block);
  });

  final blocks3 = y.YArray();
  final blocks3block = y.YMap();
  doc.transact((_) {
    blocks3block.set('text', '3');
    blocks3.push([blocks3block]);
    text.set('blocks', blocks3block);
  });

  final blocks4 = y.YArray();
  final blocks4block = y.YMap();
  doc.transact((_) {
    blocks4block.set('text', '4');
    blocks4.push([blocks4block]);
    text.set('blocks', blocks4block);
  });

  // {"text":{"blocks":{"text":"4"}}}
  undoManager.undo(); // {"text":{"blocks":{"3"}}}
  undoManager.undo(); // {"text":{"blocks":{"text":"2"}}}
  undoManager.undo(); // {"text":{"blocks":{"text":"1"}}}
  undoManager.undo(); // {}
  undoManager.redo(); // {"text":{"blocks":{"text":"1"}}}
  undoManager.redo(); // {"text":{"blocks":{"text":"2"}}}
  undoManager.redo(); // {"text":{"blocks":{"text":"3"}}}
  undoManager.redo(); // {"text":{}}
  expect(design.toJSON(), equals({ 'text': { 'blocks': { 'text': '4' } } }));
}

/**
 * Undo text formatting delete should not corrupt peer state.
 *
 * @see https://github.com/yjs/yjs/issues/392
 * @param {t.TestCase} _tc
 */
void testUndoDeleteTextFormat(t.TestCase _tc) {
  final doc = y.Doc();
  final text = doc.getText();
  text.insert(0, 'Attack ships on fire off the shoulder of Orion.');
  final doc2 = y.Doc();
  final text2 = doc2.getText();
  y.applyUpdate(doc2, y.encodeStateAsUpdate(doc));
  final undoManager = y.UndoManager(text);

  text.format(13, 7, { 'bold': true });
  undoManager.stopCapturing();
  y.applyUpdate(doc2, y.encodeStateAsUpdate(doc));

  text.format(16, 4, { 'bold': null });
  undoManager.stopCapturing();
  y.applyUpdate(doc2, y.encodeStateAsUpdate(doc));

  undoManager.undo();
  y.applyUpdate(doc2, y.encodeStateAsUpdate(doc));

  final result = [
    { 'insert': 'Attack ships ' },
    {
      'insert': 'on fire',
      'attributes': { 'bold': true }
    },
    { 'insert': ' off the shoulder of Orion.' }
  ];
  expect(text.toDelta(), equals(result));
  expect(text2.toDelta(), equals(result));
}

/**
 * Undo text formatting delete should not corrupt peer state.
 *
 * @see https://github.com/yjs/yjs/issues/392
 * @param {t.TestCase} _tc
 */
void testBehaviorOfIgnoreremotemapchangesProperty(t.TestCase _tc) {
  final doc = y.Doc();
  final doc2 = y.Doc();
  doc.on('update', (args) => y.applyUpdate(doc2, args[0] as Uint8List, doc));
  doc2.on('update', (args) => y.applyUpdate(doc, args[0] as Uint8List, doc2));
  final map1 = doc.getMap();
  final map2 = doc2.getMap();
  final um1 = y.UndoManager(map1, ignoreRemoteMapChanges: true);
  map1.set('x', 1);
  map2.set('x', 2);
  map1.set('x', 3);
  map2.set('x', 4);
  um1.undo();
  expect(map1.get('x'), 2);
  expect(map2.get('x'), 2);
}

/**
 * Special deletion case.
 *
 * @see https://github.com/yjs/yjs/issues/447
 * @param {t.TestCase} _tc
 */
void testSpecialDeletionCase(t.TestCase _tc) {
  final origin = 'undoable';
  final doc = y.Doc();
  final fragment = doc.getXmlFragment();
  final undoManager = y.UndoManager(fragment, trackedOrigins: {origin});
  doc.transact((_) {
    final e = y.YXmlElement('test');
    e.setAttribute('a', '1');
    e.setAttribute('b', '2');
    fragment.insert(0, [e]);
  });
  expect(fragment.toString(), '<test a="1" b="2"></test>');
  doc.transact((_) {
    // change attribute "b" and delete test-node
    final e = fragment.get(0) as y.YXmlElement;
    e.setAttribute('b', '3');
    fragment.delete(0);
  }, origin);
  expect(fragment.toString(), '');
  undoManager.undo();
  expect(fragment.toString(), '<test a="1" b="2"></test>');
}

/**
 * Deleted entries in a map should be restored on undo.
 *
 * @see https://github.com/yjs/yjs/issues/500
 * @param {t.TestCase} tc
 */
void testUndoDeleteInMap(t.TestCase tc) {
  final results = init(tc, users: 3),
    map0 = results['map0'] as YMap;
  final undoManager = y.UndoManager(map0, captureTimeout: 0);
  map0.set('a', 'a');
  map0.delete('a');
  map0.set('a', 'b');
  map0.delete('a');
  map0.set('a', 'c');
  map0.delete('a');
  map0.set('a', 'd');
  expect(map0.toJSON(), equals({ 'a': 'd' }));
  undoManager.undo();
  expect(map0.toJSON(), equals({}));
  undoManager.undo();
  expect(map0.toJSON(), equals({ 'a': 'c' }));
  undoManager.undo();
  expect(map0.toJSON(), equals({}));
  undoManager.undo();
  expect(map0.toJSON(), equals({ 'a': 'b' }));
  undoManager.undo();
  expect(map0.toJSON(), equals({}));
  undoManager.undo();
  expect(map0.toJSON(), equals({ 'a': 'a' }));
}

/**
 * It should expose the StackItem being processed if undoing
 *
 * @param {t.TestCase} _tc
 */
Future<void> testUndoDoingStackItem(t.TestCase _tc) async {
  final doc = y.Doc();
  final text = doc.getText('text');
  final undoManager = y.UndoManager([text]);
  undoManager.on('stack-item-added', /** @param {any} event */ (params) {
    final event = fromUndoEventData(params);
    event.stackItem.meta.set('str', '42');
  });
  // var metaUndo = /** @type {any} */ (null);
  // var metaRedo = /** @type {any} */ (null);
  var metaUndo, metaRedo;
  text.observe((event, _) {
    final /** @type {Y.UndoManager} */ origin = event.transaction.origin;
    if (origin == undoManager && (origin as UndoManager).undoing) {
      metaUndo = origin.currStackItem?.meta.get('str');
    } else if (origin == undoManager && (origin as UndoManager).redoing) {
      metaRedo = origin.currStackItem?.meta.get('str');
    }
  });
  text.insert(0, 'abc');
  undoManager.undo();
  undoManager.redo();
  expect(metaUndo, '42', reason: 'currStackItem is accessible while undoing');
  expect(metaRedo, '42', reason: 'currStackItem is accessible while redoing');
  expect(undoManager.currStackItem, null, reason: 'currStackItem is null after observe/transaction');
}
