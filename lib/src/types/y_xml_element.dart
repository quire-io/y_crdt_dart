// import * as object from 'lib0/object'

// import {
//   YXmlFragment,
//   transact,
//   typeMapDelete,
//   typeMapHas,
//   typeMapSet,
//   typeMapGet,
//   typeMapGetAll,
//   typeMapGetAllSnapshot,
//   typeListForEach,
//   YXmlElementRefID,
//   Snapshot, YXmlText, ContentType, AbstractType, UpdateDecoderV1, UpdateDecoderV2, UpdateEncoderV1, UpdateEncoderV2, Doc, Item // eslint-disable-line
// } from '../internals.js'

import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/types/y_xml_fragment.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/snapshot.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';

/**
 * @typedef {Object|number|null|Array<any>|string|Uint8Array|AbstractType<any>} ValueTypes
 */

/**
 * An YXmlElement imitates the behavior of a
 * https://developer.mozilla.org/en-US/docs/Web/API/Element|Dom Element
 *
 * * An YXmlElement has attributes (key value pairs)
 * * An YXmlElement has childElements that must inherit from YXmlElement
 *
 * @template {{ [key: string]: ValueTypes }} [KV={ [key: string]: string }]
 */
class YXmlElement extends YXmlFragment {
  YXmlElement([this.nodeName = 'UNDEFINED']);

  final String nodeName;

  /**
   * @type {Map<string, any>|null}
   */
  Map<String, Object?>? _prelimAttrs = {};

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

  /**
   * Integrate this type into the Yjs instance.
   *
   * * Save this struct in the os
   * * This type is sent to other client
   * * Observer functions are fired
   *
   * @param {Doc} y The Yjs instance
   * @param {Item} item
   */
  @override
  void innerIntegrate(Doc y, Item? item) {
    super.innerIntegrate(y, item);
    ;(/** @type {Map<string, any>} */ (this._prelimAttrs))!.forEach((key, value) {
      this.setAttribute(key, value);
    });
    this._prelimAttrs = null;
  }

  /**
   * Creates an Item with the same effect as this Item (without position effect)
   *
   * @return {YXmlElement}
   */
  @override
  YXmlElement innerCopy() {
    return YXmlElement(this.nodeName);
  }

  /**
   * Makes a copy of this data type that can be included somewhere else.
   *
   * Note that the content is only readable _after_ it has been included somewhere in the Ydoc.
   *
   * @return {YXmlElement<KV>}
   */
  @override
  YXmlElement clone() {
    /**
     * @type {YXmlElement<KV>}
     */
    final el = YXmlElement(this.nodeName);
    final attrs = this.getAttributes();
    attrs.forEach((key, value) {
      if (value is String) {
        el.setAttribute(key, value);
      }
    });
    // @ts-ignore
    el.insert(0, this.toArray().map((item) => item.clone()).toList());
    return el;
  }

  /**
   * Returns the XML serialization of this YXmlElement.
   * The attributes are ordered by attribute-name, so you can easily use this
   * method to compare YXmlElements
   *
   * @return {string} The string representation of this type.
   *
   * @public
   */
  @override
  String toString() {
    final attrs = this.getAttributes();
    final stringBuilder = <String>[];
    final keys = <String>[];
    for (final key in attrs.keys) {
      keys.add(key);
    }
    keys.sort();
    final keysLen = keys.length;
    for (var i = 0; i < keysLen; i++) {
      final key = keys[i];
      stringBuilder.add(key + '="' + attrs[key] + '"');
    }
    final nodeName = this.nodeName.toLowerCase();
    final attrsString = stringBuilder.length > 0 ? ' ' + stringBuilder.join(' ') : '';
    return '<${nodeName}${attrsString}>${super.toString()}</${nodeName}>';
  }

  /**
   * Removes an attribute from this YXmlElement.
   *
   * @param {string} attributeName The attribute name that is to be removed.
   *
   * @public
   */
  void removeAttribute(String attributeName) {
    final doc = this.doc;
    if (doc != null) {
      transact(doc, (transaction) {
        typeMapDelete(transaction, this, attributeName);
      });
    } else {
      /** @type {Map<string,any>} */ (this._prelimAttrs)!.remove(attributeName);
    }
  }

  /**
   * Sets or updates an attribute.
   *
   * @template {keyof KV & string} KEY
   *
   * @param {KEY} attributeName The attribute name that is to be set.
   * @param {KV[KEY]} attributeValue The attribute value that is to be set.
   *
   * @public
   */
  void setAttribute(String attributeName, dynamic attributeValue) {
    final doc = this.doc;
    if (doc != null) {
      transact(doc, (transaction) {
        typeMapSet(transaction, this, attributeName, attributeValue);
      });
    } else {
      /** @type {Map<string, any>} */ (this._prelimAttrs)![attributeName] = attributeValue;
    }
  }

  /**
   * Returns an attribute value that belongs to the attribute name.
   *
   * @template {keyof KV & string} KEY
   *
   * @param {KEY} attributeName The attribute name that identifies the
   *                               queried value.
   * @return {KV[KEY]|undefined} The queried attribute value.
   *
   * @public
   */
  dynamic getAttribute(String attributeName) {
    return /** @type {any} */ (typeMapGet(this, attributeName));
  }

  /**
   * Returns whether an attribute exists
   *
   * @param {string} attributeName The attribute name to check for existence.
   * @return {boolean} whether the attribute exists.
   *
   * @public
   */
  bool hasAttribute(String attributeName) {
    return /** @type {any} */ (typeMapHas(this, attributeName));
  }

  /**
   * Returns all attribute name/value pairs in a JSON Object.
   *
   * @param {Snapshot} [snapshot]
   * @return {{ [Key in Extract<keyof KV,string>]?: KV[Key]}} A JSON Object that describes the attributes.
   *
   * @public
   */
  Map<String, dynamic> getAttributes([Snapshot? snapshot]) {
    return /** @type {any} */ (snapshot != null ? typeMapGetAllSnapshot(this, snapshot) : typeMapGetAll(this));
  }

  /**
   * Creates a Dom Element that mirrors this YXmlElement.
   *
   * @param {Document} [_document=document] The document object (you must define
   *                                        this when calling this method in
   *                                        nodejs)
   * @param {Object<string, any>} [hooks={}] Optional property to customize how hooks
   *                                             are presented in the DOM
   * @param {any} [binding] You should not set this property. This is
   *                               used if DomBinding wants to create a
   *                               association to the created DOM type.
   * @return {Node} The {@link https://developer.mozilla.org/en-US/docs/Web/API/Element|Dom Element}
   *
   * @public
   */
  //TODO:
  // toDOM (_document = document, hooks = {}, binding) {
  //   final dom = _document.createElement(this.nodeName)
  //   final attrs = this.getAttributes()
  //   for (final key in attrs) {
  //     final value = attrs[key]
  //     if (typeof value === 'string') {
  //       dom.setAttribute(key, value)
  //     }
  //   }
  //   typeListForEach(this, yxml => {
  //     dom.appendChild(yxml.toDOM(_document, hooks, binding))
  //   })
  //   if (binding !== undefined) {
  //     binding._createAssociation(dom, this)
  //   }
  //   return dom
  // }

  /**
   * Transform the properties of this type to binary and write it to an
   * BinaryEncoder.
   *
   * This is called when this Item is sent to a remote peer.
   *
   * @param {UpdateEncoderV1 | UpdateEncoderV2} encoder The encoder to write data to.
   */
  @override
  void innerWrite(AbstractUpdateEncoder encoder) {
    encoder.writeTypeRef(YXmlElementRefID);
    encoder.writeKey(this.nodeName);
  }
}

/**
 * @param {UpdateDecoderV1 | UpdateDecoderV2} decoder
 * @return {YXmlElement}
 *
 * @function
 */
YXmlElement readYXmlElement(AbstractUpdateDecoder decoder) => YXmlElement(decoder.readKey());
