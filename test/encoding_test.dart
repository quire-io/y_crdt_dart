// import * as t from 'lib0/testing'
// import * as promise from 'lib0/promise'

// import {
//   contentRefs,
//   readContentBinary,
//   readContentDeleted,
//   readContentString,
//   readContentJSON,
//   readContentEmbed,
//   readContentType,
//   readContentFormat,
//   readContentAny,
//   readContentDoc,
//   Doc,
//   PermanentUserData,
//   encodeStateAsUpdate,
//   applyUpdate
// } from '../src/internals.js'

// import * as Y from '../src/index.js'

import 'dart:typed_data';

import "package:test/test.dart";

import "package:y_crdt/src/lib0/testing.dart" as t;
import "package:y_crdt/src/utils/encoding.dart";
import "package:y_crdt/src/utils/permanent_user_data.dart";
import "package:y_crdt/src/structs/item.dart";

import 'package:y_crdt/y_crdt.dart' as y;

void main() {
  group('encoding', () {

    test('struct references', () {
      testStructReferences(t.TestCase('encoding', 'struct references'));
    });
    test('permanent user data', () async {
      await testPermanentUserData(t.TestCase('encoding', 'permanent user data'));
    });

    test('diff state vector of update is empty', () {
      testDiffStateVectorOfUpdateIsEmpty(
          t.TestCase('encoding', 'diff state vector of update is empty'));
    });

    test('diff state vector of update ignores skips', () {
      testDiffStateVectorOfUpdateIgnoresSkips(
          t.TestCase('encoding', 'diff state vector of update ignores skips'));
    });

  });
}

/**
 * @param {t.TestCase} tc
 */
void testStructReferences(t.TestCase tc) {
  expect(contentRefs.length, 11);
  expect(contentRefs[1], readContentDeleted);
  expect(contentRefs[2], readContentJSON); // TODO: deprecate content json?
  expect(contentRefs[3], readContentBinary);
  expect(contentRefs[4], readContentString);
  expect(contentRefs[5], readContentEmbed);
  expect(contentRefs[6], readContentFormat);
  expect(contentRefs[7], readContentType);
  expect(contentRefs[8], readContentAny);
  expect(contentRefs[9], readContentDoc);
  // contentRefs[10] is reserved for Skip structs
}

/**
 * There is some custom encoding/decoding happening in PermanentUserData.
 * This is why it landed here.
 *
 * @param {t.TestCase} tc
 */
Future testPermanentUserData(t.TestCase tc) async {
  final ydoc1 = y.Doc();
  final ydoc2 = y.Doc();
  final pd1 = PermanentUserData(ydoc1);
  final pd2 = PermanentUserData(ydoc2);
  pd1.setUserMapping(ydoc1, ydoc1.clientID, 'user a');
  pd2.setUserMapping(ydoc2, ydoc2.clientID, 'user b');
  ydoc1.getText().insert(0, 'xhi');
  ydoc1.getText().delete(0, 1);
  ydoc2.getText().insert(0, 'hxxi');
  ydoc2.getText().delete(1, 2);
  await Future.delayed(Duration(milliseconds: 10));
  applyUpdate(ydoc2, encodeStateAsUpdate(ydoc1));
  applyUpdate(ydoc1, encodeStateAsUpdate(ydoc2));

  // now sync a third doc with same name as doc1 and then create PermanentUserData
  final ydoc3 = y.Doc();
  applyUpdate(ydoc3, encodeStateAsUpdate(ydoc1));
  final pd3 = PermanentUserData(ydoc3);
  pd3.setUserMapping(ydoc3, ydoc3.clientID, 'user a');
}

/**
 * Reported here: https://github.com/yjs/yjs/issues/308
 * @param {t.TestCase} tc
 */
void testDiffStateVectorOfUpdateIsEmpty(t.TestCase tc) {
  final ydoc = y.Doc();
  /**
   * @type {any}
   */
  Uint8List? sv;
  ydoc.getText().insert(0, 'a');
  ydoc.on('update', (params) {
    final update = params[0] as Uint8List;
    sv = y.encodeStateVectorFromUpdate(update);
  });
  // should produce an update with an empty state vector (because previous ops are missing)
  ydoc.getText().insert(0, 'a');
  expect(sv != null && sv!.lengthInBytes == 1 && sv![0] == 0, isTrue);
}

/**
 * Reported here: https://github.com/yjs/yjs/issues/308
 * @param {t.TestCase} tc
 */
void testDiffStateVectorOfUpdateIgnoresSkips(t.TestCase tc) {
  final ydoc = y.Doc();
  /**
   * @type {Array<Uint8Array>}
   */
  final updates = <Uint8List>[];
  ydoc.on('update', (params) {
    final update = params[0] as Uint8List;
    updates.add(update);
  });
  ydoc.getText().insert(0, 'a');
  ydoc.getText().insert(0, 'b');
  ydoc.getText().insert(0, 'c');
  final update13 = y.mergeUpdates([updates[0], updates[2]]);
  final sv = y.encodeStateVectorFromUpdate(update13);
  final state = y.decodeStateVector(sv);
  expect(state.get(ydoc.clientID), 1);
  expect(state.length, 1);
}
