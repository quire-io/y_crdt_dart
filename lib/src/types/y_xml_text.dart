// import {
//   YText,
//   YXmlTextRefID,
//   ContentType, YXmlElement, UpdateDecoderV1, UpdateDecoderV2, UpdateEncoderV1, UpdateEncoderV2, // eslint-disable-line
// } from '../internals.js'

import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/types/y_text.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';

/**
 * Represents text in a Dom Element. In the future this type will also handle
 * simple formatting information like bold and italic.
 */
class YXmlText extends YText {

  YXmlText([super.string]);
  /**
   * @type {YXmlElement|YXmlText|null}
   */
  AbstractType? get nextSibling {
    final n = this.innerItem?.next;
    // return n ? /** @type {YXmlElement|YXmlText} */ (/** @type {ContentType} */ (n.content).type) : null
    return (n?.content as ContentType?)?.type;
  }

  /**
   * @type {YXmlElement|YXmlText|null}
   */
  AbstractType? get prevSibling { 
    final n = this.innerItem?.prev;
    //return n ? /** @type {YXmlElement|YXmlText} */ (/** @type {ContentType} */ (n.content).type) : null
    return (n?.content as ContentType?)?.type;
  }

  @override
  YXmlText innerCopy () {
    return YXmlText();
  }

  /**
   * Makes a copy of this data type that can be included somewhere else.
   *
   * Note that the content is only readable _after_ it has been included somewhere in the Ydoc.
   *
   * @return {YXmlText}
   */
  @override
  YXmlText clone() {
    final text = YXmlText();
    text.applyDelta(this.toDelta());
    return text;
  }

  /**
   * Creates a Dom Element that mirrors this YXmlText.
   *
   * @param {Document} [_document=document] The document object (you must define
   *                                        this when calling this method in
   *                                        nodejs)
   * @param {Object<string, any>} [hooks] Optional property to customize how hooks
   *                                             are presented in the DOM
   * @param {any} [binding] You should not set this property. This is
   *                               used if DomBinding wants to create a
   *                               association to the created DOM type.
   * @return {Text} The {@link https://developer.mozilla.org/en-US/docs/Web/API/Element|Dom Element}
   *
   * @public
   */
  //TODO:
  // toDOM (Document _document, hooks, binding) {
  //   final dom = _document.createTextNode(this.toString())
  //   if (binding !== undefined) {
  //     binding._createAssociation(dom, this)
  //   }
  //   return dom
  // }

  @override
  String toString () {
    // @ts-ignore
    return this.toDelta().map((delta) {
      final nestedNodes = <({int nodeName, List<MapEntry<int, Object?>> attrs})>[],
        attributes = delta['attributes'] as Map? ?? {};
      for (final nodeName in attributes.keys) {
        final attrs = <MapEntry<int, Object?>>[],
          values = attributes[nodeName] as Map;
        for (final key in values.keys) {
          attrs.add(MapEntry(key as int, values[key]));
        }
        // sort attributes to get a unique order
        attrs.sort((a, b) => a.key < b.key ? -1 : 1);
        nestedNodes.add((nodeName: nodeName, attrs: attrs));
      }
      // sort node order to get a unique order
      nestedNodes.sort((a, b) => a.nodeName < b.nodeName ? -1 : 1);
      // now convert to dom string
      var str = '';
      for (var i = 0; i < nestedNodes.length; i++) {
        final node = nestedNodes[i];
        str += '<${node.nodeName}';
        for (var j = 0; j < node.attrs.length; j++) {
          final attr = node.attrs[j];
          str += ' ${attr.key}="${attr.value}"';
        }
        str += '>';
      }
      str += '${delta['insert']}';
      for (var i = nestedNodes.length - 1; i >= 0; i--) {
        str += '</${nestedNodes[i].nodeName}>';
      }
      return str;
    }).join('');
  }

  /**
   * @return {string}
   */
  @override
  String toJSON () {
    return this.toString();
  }

  /**
   * @param {UpdateEncoderV1 | UpdateEncoderV2} encoder
   */
  @override
  void innerWrite(AbstractUpdateEncoder encoder) {
    encoder.writeTypeRef(YXmlTextRefID);
  }
}

/**
 * @param {UpdateDecoderV1 | UpdateDecoderV2} decoder
 * @return {YXmlText}
 *
 * @private
 * @function
 */
YXmlText readYXmlText(AbstractUpdateDecoder decoder) => YXmlText();
