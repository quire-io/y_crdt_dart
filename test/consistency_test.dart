library;

import "package:test/test.dart";

import 'package:y_crdt/y_crdt.dart' as y;
import "package:dart_quill_delta/dart_quill_delta.dart";

void main() {
  test('IdDuplicateChange', () {
    /**
     const doc1 = new Y.Doc()
  doc1.clientID = 0
  const doc2 = new Y.Doc()
  doc2.clientID = 0
  t.assert(doc2.clientID === doc1.clientID)
  doc1.getArray('a').insert(0, [1, 2])
  Y.applyUpdate(doc2, Y.encodeStateAsUpdate(doc1))
  t.assert(doc2.clientID !== doc1.clientID)
     */

    final doc1 = y.Doc();
    doc1.clientID = 0;
    final doc2 = y.Doc();
    doc2.clientID = 0;

    expect(doc2.clientID, equals(doc1.clientID));

    doc1.getArray('a').insert(0, [1, 2]);
    final stateVector = y.encodeStateVector(doc2);
    y.applyUpdate(doc2, y.encodeStateAsUpdate(doc1, stateVector), stateVector);

    expect(doc2.clientID, isNot(equals(doc1.clientID)));
  });
}