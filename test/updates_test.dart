// import * as t from 'lib0/testing'
// import { init, compare } from './testHelper.js' // eslint-disable-line
// import * as Y from '../src/index.js'
// import { readClientsStructRefs, readDeleteSet, UpdateDecoderV2, UpdateEncoderV2, writeDeleteSet } from '../src/internals.js'
// import * as encoding from 'lib0/encoding'
// import * as decoding from 'lib0/decoding'
// import * as object from 'lib0/object'

import 'dart:typed_data';

import "package:test/test.dart";

import "package:y_crdt/src/lib0/encoding.dart" as encoding;
import "package:y_crdt/src/lib0/decoding.dart" as decoding;
import "package:y_crdt/src/lib0/testing.dart" as t;
import "package:y_crdt/src/utils/delete_set.dart";
import "package:y_crdt/src/utils/encoding.dart";
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import "package:y_crdt/src/types/y_text.dart";
import "package:y_crdt/src/types/y_array.dart";

import 'package:y_crdt/y_crdt.dart' as y;

import "test_helper.dart";


void main() {
  group('Updates', () {

    test('merge updates', () {
      testMergeUpdates(t.TestCase('doc', 'merge updates'));
    });

    test('key encoding', () {
      testKeyEncoding(t.TestCase('doc', 'key encoding'));
    });

    //TODOL upgrade YArray
    // test('merge updates 1', () {
    //   testMergeUpdates1(t.TestCase('doc', 'merge updates 1'));
    // });

    // test('merge updates 2', () {
    //   testMergeUpdates2(t.TestCase('doc', 'merge updates 2'));
    // });

    test('merge pending updates', () {
      testMergePendingUpdates(t.TestCase('doc', 'merge pending updates'));
    });

    test('obfuscate updates', () {
      testObfuscateUpdates(t.TestCase('doc', 'obfuscate updates'));
    });
  });
}

final encV1 = EncV1();
final encV2 = EncV2();
final encDoc = EncDoc();

class EncDoc extends Enc {
  EncDoc() : super('updateV2', 'Merge via Y.Doc');

  @override
  Uint8List encodeStateVector(y.Doc doc) {
    return y.encodeStateVector(false, doc);
  }

  @override
  Uint8List encodeStateAsUpdate(y.Doc doc, [Uint8List? encodedTargetStateVector]) {
    return y.encodeStateAsUpdateV2(false, doc, encodedTargetStateVector);
  }

  @override
  Uint8List encodeStateVectorFromUpdate(Uint8List update) {
    return y.encodeStateVectorFromUpdateV2(false, update);
  }

  @override
  Uint8List mergeUpdates(Iterable<Uint8List> updates) {
    final ydoc = y.Doc(gc: false);
    updates.forEach((update) {
      y.applyUpdateV2(false, ydoc, update);
    });
    return y.encodeStateAsUpdateV2(false, ydoc); 
  }

  @override
  void applyUpdate(y.Doc ydoc, Uint8List update, [dynamic transactionOrigin]) {
    y.applyUpdateV2(false, ydoc, update, transactionOrigin);
  }

  @override
  void logUpdate(Uint8List update) {
    y.logUpdateV2(false, update);
  }

  @override
  Uint8List diffUpdate(Uint8List update, Uint8List sv) {
    final ydoc = y.Doc(gc: false);
    y.applyUpdateV2(false, ydoc, update);
    return y.encodeStateAsUpdateV2(false, ydoc, sv);
  }

  @override
  (Map<int, int>, Map<int, int>) parseUpdateMeta(Uint8List update) {
    return y.parseUpdateMetaV2(false, update);
  }
}

final encoders = [encV1, encV2, encDoc];

/**
 * @param {Array<Y.Doc>} users
 * @param {Enc} enc
 */
y.Doc fromUpdates(List<y.Doc> users, Enc enc) {
  final updates = users.map((user) {
    return enc.encodeStateAsUpdate(user);
  });
  final ydoc = y.Doc();
  enc.applyUpdate(ydoc, enc.mergeUpdates(updates));
  return ydoc;
}

/**
 * @param {t.TestCase} tc
 */
void testMergeUpdates(t.TestCase tc) {
  final results = init(tc, users: 3 ),
    users = results['users'] as List,
    array0 = results['array0'] as YArray,
    array1 = results['array1'] as YArray;

  array0.insert(0, [1]);
  array1.insert(0, [2]);

  compare(users);
  encoders.forEach((enc) {
    final merged = fromUpdates(users.cast(), enc);
    expect(array0.toArray(), equals(merged.getArray('array').toArray()));
  });
}

/**
 * @param {t.TestCase} tc
 */
void testKeyEncoding(t.TestCase tc) {
  final results = init(tc, users: 2 ),
    users = results['users'] as List,
    text0 = results['text0'] as YText,
    text1 = results['text1'] as YText;

  text0.insert(0, 'a', { 'italic': true });
  text0.insert(0, 'b');
  text0.insert(0, 'c', { 'italic': true });

  final update = y.encodeStateAsUpdateV2(false, users[0]);
  y.applyUpdateV2(false, users[1], update);

  expect(text1.toDelta(), equals([
    { 'insert': 'c', 'attributes': { 'italic': true } },
    { 'insert': 'b' }, 
    { 'insert': 'a', 'attributes': { 'italic': true } }
  ]));

  compare(users);
}

/**
 * @param {Y.Doc} ydoc
 * @param {Array<Uint8Array>} updates - expecting at least 4 updates
 * @param {Enc} enc
 * @param {boolean} hasDeletes
 */
void checkUpdateCases(y.Doc ydoc, List<Uint8List> updates, Enc enc, bool hasDeletes) {
  final cases = <Uint8List>[];
  // Case 1: Simple case, simply merge everything
  cases.add(enc.mergeUpdates(updates));

  // Case 2: Overlapping updates
  cases.add(enc.mergeUpdates([
    enc.mergeUpdates(updates.sublist(2)),
    enc.mergeUpdates(updates.sublist(0, 2))
  ]));

  // Case 3: Overlapping updates
  cases.add(enc.mergeUpdates([
    enc.mergeUpdates(updates.sublist(2)),
    enc.mergeUpdates(updates.sublist(1, 3)),
    updates[0]
  ]));

  // Case 4: Separated updates (containing skips)
  cases.add(enc.mergeUpdates([
    enc.mergeUpdates([updates[0], updates[2]]),
    enc.mergeUpdates([updates[1], updates[3]]),
    enc.mergeUpdates(updates.sublist(4))
  ]));

  // Case 5: overlapping with many duplicates
  cases.add(enc.mergeUpdates(cases));

  // final targetState = enc.encodeStateAsUpdate(ydoc)
  // print('Target State: ')
  // enc.logUpdate(targetState)

  cases.forEach((mergedUpdates) {
    // print('State Case $' + i + ':')
    // enc.logUpdate(updates)
    final merged = y.Doc(gc: false);
    enc.applyUpdate(merged, mergedUpdates);
    expect(merged.getArray().toArray(), equals(ydoc.getArray().toArray()));
    expect(enc.encodeStateVector(merged), equals(enc.encodeStateVectorFromUpdate(mergedUpdates)));

    if (enc.updateEventName != 'update') { // @todo should this also work on legacy updates?
      for (var j = 1; j < updates.length; j++) {
        final partMerged = enc.mergeUpdates(updates.sublist(j));
        final partMeta = enc.parseUpdateMeta(partMerged);
        final targetSV = y.encodeStateVectorFromUpdateV2(false, y.mergeUpdatesV2(false, updates.sublist(0, j)));
        final diffed = enc.diffUpdate(mergedUpdates, targetSV);
        final diffedMeta = enc.parseUpdateMeta(diffed);
        expect(partMeta, equals(diffedMeta));
        {
          // We can'd do the following
          //  - expect(diffed, mergedDeletes)
          // because diffed contains the set of all deletes.
          // So we add all deletes from `diffed` to `partDeletes` and compare then
          final decoder = decoding.createDecoder(diffed, false);
          final updateDecoder = UpdateDecoderV2(decoder);
          readClientsStructRefs(updateDecoder, y.Doc());
          final ds = readDeleteSet(updateDecoder);
          final updateEncoder = UpdateEncoderV2(false);
          encoding.writeVarUint(updateEncoder.restEncoder, 0); // 0 structs
          writeDeleteSet(updateEncoder, ds);
          final deletesUpdate = updateEncoder.toUint8Array();
          final mergedDeletes = y.mergeUpdatesV2(false, [deletesUpdate, partMerged]);
          if (!hasDeletes || enc != encDoc) {
            // deletes will almost definitely lead to different encoders because of the mergeStruct feature that is present in encDoc
            expect(diffed, equals(mergedDeletes));
          }
        }
      }
    }

    final (from, to) = enc.parseUpdateMeta(mergedUpdates);
    from.forEach((client, clock) => expect(clock, 0));
    to.forEach((client, clock) {
      final structs = /** @type {Array<Y.Item>} */ (merged.store.clients.get(client)) as List<y.AbstractStruct>;
      final lastStruct = structs[structs.length - 1];
      expect(lastStruct.id.clock + lastStruct.length, clock);
    });
  });
}

/**
 * @param {t.TestCase} _tc
 */
void testMergeUpdates1(t.TestCase _tc) {
  encoders.forEach((enc) {
    print('Using encoder: ${enc.description}');
    final ydoc = y.Doc(gc: false);
    final updates = /** @type {Array<Uint8Array>} */ (<Uint8List>[]);
    ydoc.on(enc.updateEventName, (params) => updates.add(params[0] as Uint8List));

    final array = ydoc.getArray();
    array.insert(0, [1]);
    array.insert(0, [2]);
    array.insert(0, [3]);
    array.insert(0, [4]);

    checkUpdateCases(ydoc, updates, enc, false);
  });
}

/**
 * @param {t.TestCase} tc
 */
void testMergeUpdates2(t.TestCase tc) {
  encoders.forEach((enc) {
    print('Using encoder: ${enc.description}');
    final ydoc = y.Doc(gc: false);
    final updates = /** @type {Array<Uint8Array>} */ (<Uint8List>[]);
    ydoc.on(enc.updateEventName, (params) => updates.add(params[0] as Uint8List));

    final array = ydoc.getArray();
    array.insert(0, [1, 2]);
    array.delete(1, 1);
    array.insert(0, [3, 4]);
    array.delete(1, 2);

    checkUpdateCases(ydoc, updates, enc, true);
  });
}

/**
 * @param {t.TestCase} tc
 */
void testMergePendingUpdates(t.TestCase tc) {
  final yDoc = y.Doc();
  /**
   * @type {Array<Uint8Array>}
   */
  final serverUpdates = <Uint8List>[];
  yDoc.on('update', (params) {
    final update = params[0] as Uint8List;
    serverUpdates.insert(serverUpdates.length, update);
  });
  final yText = yDoc.getText('textBlock');
  yText.applyDelta([{ 'insert': 'r' }]);
  yText.applyDelta([{ 'insert': 'o' }]);
  yText.applyDelta([{ 'insert': 'n' }]);
  yText.applyDelta([{ 'insert': 'e' }]);
  yText.applyDelta([{ 'insert': 'n' }]);

  final yDoc1 = y.Doc();
  y.applyUpdate(false, yDoc1, serverUpdates[0]);
  final update1 = y.encodeStateAsUpdate(false, yDoc1);

  final yDoc2 = y.Doc();
  y.applyUpdate(false, yDoc2, update1);
  y.applyUpdate(false, yDoc2, serverUpdates[1]);
  final update2 = y.encodeStateAsUpdate(false, yDoc2);

  final yDoc3 = y.Doc();
  y.applyUpdate(false, yDoc3, update2);
  y.applyUpdate(false, yDoc3, serverUpdates[3]);
  final update3 = y.encodeStateAsUpdate(false, yDoc3);

  final yDoc4 = y.Doc();
  y.applyUpdate(false, yDoc4, update3);
  y.applyUpdate(false, yDoc4, serverUpdates[2]);
  final update4 = y.encodeStateAsUpdate(false, yDoc4);

  final yDoc5 = y.Doc();
  y.applyUpdate(false, yDoc5, update4);
  y.applyUpdate(false, yDoc5, serverUpdates[4]);
  // @ts-ignore
  // ignore: unused_local_variable
  final _update5 = y.encodeStateAsUpdate(false, yDoc5); // eslint-disable-line

  final yText5 = yDoc5.getText('textBlock');
  expect(yText5.toString(), 'nenor');
}

/**
 * @param {t.TestCase} _tc
 */
void testObfuscateUpdates(t.TestCase _tc) {
  final ydoc = y.Doc();
  final ytext = ydoc.getText('text');
  final ymap = ydoc.getMap('map');
  final yarray = ydoc.getArray('array');
  // test ytext
  ytext.applyDelta([
    { 'insert': 'text', 'attributes': { 'bold': true } }, 
    { 'insert': { 'href': 'supersecreturl' } }]);
  // test ymap
  ymap.set('key', 'secret1');
  ymap.set('key', 'secret2');
  // test yarray with subtype & subdoc
  final subtype = y.YXmlElement('secretnodename');
  final subdoc = y.Doc(guid: 'secret');
  subtype.setAttribute('attr', 'val');
  yarray.insert(0, ['teststring', 42, subtype, subdoc]);
  // obfuscate the content and put it into a new document
  final obfuscatedUpdate = y.obfuscateUpdate(y.encodeStateAsUpdate(false, ydoc));
  final odoc = y.Doc();
  y.applyUpdate(false, odoc, obfuscatedUpdate);
  final otext = odoc.getText('text');
  final omap = odoc.getMap('map');
  final oarray = odoc.getArray('array');
  // test ytext
  final delta = otext.toDelta();
  expect(delta.length, 2);
  expect(delta[0]['insert'] != 'text' && (delta[0]['insert'] as String).length == 4, true);
  expect((delta[0]['attributes'] as Map).length, 1);
  expect((delta[0]['attributes'] as Map).containsKey('bold'), false);
  expect((delta[1] as Map).length, 1);
  expect((delta[1] as Map).containsKey('insert'), true);
  // test ymap
  expect(omap.size, 1);
  expect(omap.has('key'), false);
  // test yarray with subtype & subdoc
  final result = oarray.toArray();
  expect(result.length, 4);
  expect(result[0], isNot('teststring'));
  expect(result[1], isNot(42));
  final osubtype = /** @type {Y.XmlElement} */ (result[2]) as y.YXmlElement;
  final osubdoc = result[3] as y.Doc;
  // test subtype
  //TODO: fix YXmlElement test case
  // expect(osubtype.nodeName, isNot(subtype.nodeName));
  expect(osubtype.getAttributes().length, 1);
  expect(osubtype.getAttribute('attr'), isNull);
  // test subdoc
  expect(osubdoc.guid != subdoc.guid, true);
}
