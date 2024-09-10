library;

import "package:test/test.dart";

import 'package:y_crdt/y_crdt.dart' as y;
import "package:dart_quill_delta/dart_quill_delta.dart";

void main() async {
  test('table conversion bug', () {
    final id = 'mytable';
    final delta = Delta.fromJson([
      {'insert': '1.1'}, {'insert': '\n', 'attributes': {'table': 1}}, 
      {'insert': '1.2'}, {'insert': '\n', 'attributes': {'table': 1, 'align': 'right'}}, 
      {'insert': '1.3'}, {'insert': '\n', 'attributes': {'table': 1}}, 

      {'insert': '2.1'}, {'insert': '\n', 'attributes': {'table': 2}}, 
      {'insert': '2.2'}, {'insert': '\n', 'attributes': {'table': 2, 'align': 'right'}}, 
      {'insert': '2.3', 'attributes': {'bold': true}}, {'insert': '\n', 'attributes': {'table': 2}}, 

      {'insert': '3.1'}, {'insert': '\n', 'attributes': {'table': 3}}, 
      {'insert': '\n', 'attributes': {'table': 3, 'align': 'right'}}, 
      {'insert': '\n', 'attributes': {'table': 3}}, {'insert': '\n'}]);
    
    final sDocText = y.Doc().getText(id)
      ..applyDelta(delta.toJson());


    expect(sDocText.toDelta(), equals(delta.toJson()));
  });
}