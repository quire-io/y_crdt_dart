library;

import "package:test/test.dart";

import 'package:y_crdt/y_crdt.dart' as y;
import "package:dart_quill_delta/dart_quill_delta.dart";

void main() {
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

  test('Remove bullet list', () {
    final id = 'mylist';
    final delta = Delta.fromJson([
      {'insert': 'item'},{'insert': '\n', 'attributes': {'list': 'bullet'}}
    ]);

    final sDocText = y.Doc().getText(id)
      ..applyDelta(delta.toJson());

    sDocText.applyDelta(Delta.fromJson([
      {'retain': 4}, {'retain': 1, 'attributes': {'list': null}}]).toJson());

    expect(sDocText.toDelta(), equals([{'insert': 'item\n'}]));
  });

  test('merge style', () {
    final ytext = y.Doc().getText('mydoc');
    ytext.applyDelta([{'insert': 'aa', 'attributes': { 'bold': true }}]);
    ytext.applyDelta([{'retain': 2}, { 'insert': 'bb', 'attributes': { 'bold': true }}]);
    ytext.applyDelta([{'retain': 2}, { 'insert': 'cc', 'attributes': { 'bold': true }}]);
    
    expect(ytext.toDelta(), equals([{'insert': 'aaccbb', 'attributes': { 'bold': true }}]));
  });

  test('list style', () {
    final ytext = y.Doc().getText('mydoc');
    ytext.applyDelta([{'insert': '\n','attributes': { 'list': 'bullet' }}]);
    ytext.applyDelta([{'insert': '1'}]);
    ytext.applyDelta([{'retain': 1}, {'insert': '\n','attributes': { 'list': 'bullet' }}]);
    ytext.applyDelta([{'retain': 2}, {'insert': '2'}]);
    expect(ytext.toDelta(), equals([
      {'insert': '1'},
      {'insert': '\n', 'attributes': { 'list': 'bullet' }},
      {'insert': '2'},
      {'insert': '\n', 'attributes': { 'list': 'bullet' }},
      ]));
  });


  test('list sync', () {
    final text1 = y.Doc().getText('mydoc');
    final text2 = y.Doc().getText('mydoc');

    text2.applyDelta([{'insert': '12\n'}]);
    syncDocUpdate(text2.doc!, text1.doc!);

    text1.applyDelta([{'retain': 2}, {'retain': 1, 'attributes': {'list': 'bullet'}},]);
    syncDocUpdate(text1.doc!, text2.doc!);

    expect(text1.toDelta(), equals(text2.toDelta()));
  });

  test('sync with BOM', () {
    final id = 'mytext',
      yText = y.Doc().getText(id)
        ..applyDelta([
          {
            "insert": "﻿Separate question. What is your availability through May 24?"
          },
          {
            "insert": "\n\n",
            "attributes": {
              "blockquote": true
            }
          },
          {
            "insert": "Thanks,"
          },
          {
            "insert": "\n\n",
            "attributes": {
              "blockquote": true
            }
          },
        ]);

    syncDocUpdate(yText.doc!, y.Doc().getText(id).doc!);
  });
}

void syncDocUpdate(y.Doc source, y.Doc target) {
  var stateVector = y.encodeStateVector(false, target),
    diff = y.encodeStateAsUpdate(false, source, stateVector);

  y.applyUpdate(false, target, diff, stateVector);
}