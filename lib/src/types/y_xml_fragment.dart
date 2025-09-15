/**
 * @module YXml
 */

// import {
//   YXmlEvent,
//   YXmlElement,
//   AbstractType,
//   typeListMap,
//   typeListForEach,
//   typeListInsertGenerics,
//   typeListInsertGenericsAfter,
//   typeListDelete,
//   typeListToArray,
//   YXmlFragmentRefID,
//   callTypeObservers,
//   transact,
//   typeListGet,
//   typeListSlice,
//   warnPrematureAccess,
//   UpdateDecoderV1, UpdateDecoderV2, UpdateEncoderV1, UpdateEncoderV2, Doc, ContentType, Transaction, Item, YXmlText, YXmlHook // eslint-disable-line
// } from '../internals.js'

// import * as error from 'lib0/error'
// import * as array from 'lib0/array'

import 'dart:collection';

import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/types/y_xml_event.dart';
import 'package:y_crdt/src/types/y_xml_element.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';

/**
 * Define the elements to which a set of CSS queries apply.
 * {@link https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Selectors|CSS_Selectors}
 *
 * @example
 *   query = '.classSelector'
 *   query = 'nodeSelector'
 *   query = '#idSelector'
 *
 * @typedef {string} CSS_Selector
 */

/**
 * Dom filter function.
 *
 * @callback domFilter
 * @param {string} nodeName The nodeName of the element
 * @param {Map} attributes The map of attributes.
 * @return {boolean} Whether to include the Dom node in the YXmlElement.
 */

bool _asTrue<T>(T _) => true;

/**
 * Represents a subset of the nodes of a YXmlElement / YXmlFragment and a
 * position within them.
 *
 * Can be created with {@link YXmlFragment#createTreeWalker}
 *
 * @public
 * @implements {Iterable<YXmlElement|YXmlText|YXmlElement|YXmlHook>}
 */
class YXmlTreeWalker with IterableMixin<AbstractType> implements Iterator<AbstractType> {
  /**
   * @param {YXmlFragment | YXmlElement} root
   * @param {function(AbstractType<any>):boolean} [f]
   */
  YXmlTreeWalker(this._root, [bool f(AbstractType elem)?]):
    this._filter = f ?? _asTrue {

    _currentNode = /** @type {Item} */ (this._root.innerStart);
    // root.doc ?? warnPrematureAccess()
  }

  final AbstractType _root;

  final bool Function(AbstractType) _filter;

  /**
   * @type {Item}
   */
  Item? _currentNode;

  var _firstCall = true;

  // [Symbol.iterator] () {
  //   return this
  // }

  /**
   * @return {IterableIterator<T>}
   */
  @override
  Iterator<AbstractType> get iterator {
    return this;
  }

  AbstractType? _current;
  @override
  AbstractType get current => _current!;

  @override
  bool moveNext() {
    final result = this.next();
    this._current = result.value;
    return result.done;
  }


  /**
   * Get the next node.
   *
   * @return {IteratorResult<YXmlElement|YXmlText|YXmlHook>} The next node.
   *
   * @public
   */
  ({AbstractType? value, bool done}) next() {
    /**
     * @type {Item|null}
     */
    Item? n = this._currentNode;
    var type = (n?.content as ContentType?)?.type;
    if (n != null && (!this._firstCall || n.deleted || !this._filter(type!))) { // if first call, we check if we can use the first item
      do {
        type = /** @type {any} */ (n!.content as ContentType).type;
        if (!n.deleted && (type is YXmlElement || type is YXmlFragment) && type.innerStart != null) {
          // walk down in the tree
          n = type.innerStart;
        } else {
          // walk right or up in the tree
          while (n != null) {
            /**
             * @type {Item | null}
             */
            final nxt = n.next;
            if (nxt != null) {
              n = nxt;
              break;
            } else if (n.parent == this._root) {
              n = null;
            } else {
              n = /** @type {AbstractType<any>} */ (n.parent as AbstractType).innerItem;
            }
          }
        }
      } while (n != null && (n.deleted || !this._filter(/** @type {ContentType} */ (n.content as ContentType).type)));
    }
    this._firstCall = false;
    if (n == null) {
      // @ts-ignore
      return (value: null, done: true);
    }
    this._currentNode = n;
    return (value: /** @type {any} */ (n.content as ContentType).type, done: false);
  }
}

/**
 * Represents a list of {@link YXmlElement}.and {@link YXmlText} types.
 * A YxmlFragment is similar to a {@link YXmlElement}, but it does not have a
 * nodeName and it does not have attributes. Though it can be bound to a DOM
 * element - in this case the attributes and the nodeName are not shared.
 *
 * @public
 * @extends AbstractType<YXmlEvent>
 */
class YXmlFragment extends AbstractType<YXmlEvent> {

  /**
   * @type {Array<any>|null}
   */
  List? _prelimContent = [];

  /**
   * @type {YXmlElement|YXmlText|null}
   */
  dynamic get firstChild {
    final first = this.innerFirst;
    // return first ? first.content.getContent()[0] : null
    return first?.content.getContent().firstOrNull;
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
    this.insert(0, /** @type {Array<any>} */ (this._prelimContent!.cast()));
    this._prelimContent = null;
  }

  @override
  YXmlFragment innerCopy() {
    return YXmlFragment();
  }

  /**
   * Makes a copy of this data type that can be included somewhere else.
   *
   * Note that the content is only readable _after_ it has been included somewhere in the Ydoc.
   *
   * @return {YXmlFragment}
   */
  @override
  YXmlFragment clone() {
    final el = YXmlFragment();
    // @ts-ignore
    el.insert(0, this.toArray().map((item) => item.clone()).toList());
    return el;
  }

  int get length {
    // this.doc ?? warnPrematureAccess()
    return this._prelimContent?.length ?? this.innerLength;
  }

  /**
   * Create a subtree of childNodes.
   *
   * @example
   * final walker = elem.createTreeWalker(dom => dom.nodeName === 'div')
   * for (var node in walker) {
   *   // `node` is a div node
   *   nop(node)
   * }
   *
   * @param {function(AbstractType<any>):boolean} filter Function that is called on each child element and
   *                          returns a Boolean indicating whether the child
   *                          is to be included in the subtree.
   * @return {YXmlTreeWalker} A subtree and a position within it.
   *
   * @public
   */
  YXmlTreeWalker createTreeWalker([bool filter(AbstractType type)?]) {
    return YXmlTreeWalker(this, filter);
  }

  /**
   * Returns the first YXmlElement that matches the query.
   * Similar to DOM's {@link querySelector}.
   *
   * Query support:
   *   - tagname
   * TODO:
   *   - id
   *   - attribute
   *
   * @param {CSS_Selector} query The query on the children.
   * @return {YXmlElement|YXmlText|YXmlHook|null} The first element that matches the query or null.
   *
   * @public
   */
  AbstractType? querySelector (String query) {
    query = query.toUpperCase();
    // @ts-ignore
    final iterator = YXmlTreeWalker(this, (element) 
      // => element.nodeName && element.nodeName.toUpperCase() == query);
      => element is YXmlElement && element.nodeName.toUpperCase() == query);
    final next = iterator.next();
    if (next.done) {
      return null;
    } else {
      return next.value;
    }
  }

  /**
   * Returns all YXmlElements that match the query.
   * Similar to Dom's {@link querySelectorAll}.
   *
   * @todo Does not yet support all queries. Currently only query by tagName.
   *
   * @param {CSS_Selector} query The query on the children
   * @return {Array<YXmlElement|YXmlText|YXmlHook|null>} The elements that match this query.
   *
   * @public
   */
  List<AbstractType> querySelectorAll(String query) {
    query = query.toUpperCase();
    // @ts-ignore
    return YXmlTreeWalker(this, (element) 
      // => element.nodeName && element.nodeName.toUpperCase() == query));
      => element is YXmlElement && element.nodeName.toUpperCase() == query).toList();
  }

  /**
   * Creates YXmlEvent and calls observers.
   *
   * @param {Transaction} transaction
   * @param {Set<null|string>} parentSubs Keys changed on this type. `null` if list was modified.
   */
  @override
  void innerCallObserver(Transaction transaction, Set<String?> parentSubs) {
    callTypeObservers(this, transaction, YXmlEvent(this, parentSubs, transaction));
  }

  /**
   * Get the string representation of all the children of this YXmlFragment.
   *
   * @return {string} The string representation of all children.
   */
  @override
  String toString () {
    return typeListMap(this, (xml, _, __) => xml.toString()).join('');
  }

  /**
   * @return {string}
   */
  @override
  String toJSON () {
    return this.toString();
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
  //   final fragment = _document.createDocumentFragment()
  //   if (binding !== undefined) {
  //     binding._createAssociation(fragment, this)
  //   }
  //   typeListForEach(this, xmlType => {
  //     fragment.insertBefore(xmlType.toDOM(_document, hooks, binding), null)
  //   })
  //   return fragment
  // }

  /**
   * Inserts new content at an index.
   *
   * @example
   *  // Insert character 'a' at position 0
   *  xml.insert(0, [new Y.XmlText('text')])
   *
   * @param {number} index The index to insert content at
   * @param {Array<YXmlElement|YXmlText>} content The array of content
   */
  void insert(int index, List content) {
    final doc = this.doc;
    if (doc != null) {
      transact(doc, (transaction) {
        typeListInsertGenerics(transaction, this, index, content);
      });
    } else {
      // @ts-ignore _prelimContent is defined because this is not yet integrated
      // this._prelimContent.splice(index, 0, ...content)
      this._prelimContent!.insertAll(index, content);
    }
  }

  /**
   * Inserts new content at an index.
   *
   * @example
   *  // Insert character 'a' at position 0
   *  xml.insert(0, [new Y.XmlText('text')])
   *
   * @param {null|Item|YXmlElement|YXmlText} ref The index to insert content at
   * @param {Array<YXmlElement|YXmlText>} content The array of content
   */
  void insertAfter(ref, content) {
    final doc = this.doc;
    if (doc != null) {
      transact(doc, (transaction) {
        final refItem = (ref && ref is AbstractType) ? ref.innerItem : ref;
        typeListInsertGenericsAfter(transaction, this, refItem, content);
      });
    } else {
      final pc = /** @type {Array<any>} */ (this._prelimContent);
      final index = ref == null ? 0 : pc!.indexWhere((el) => el == ref) + 1;
      if (index == 0 && ref != null) {
        throw Exception('Reference item not found');
        // throw error.create('Reference item not found')
      }
      // pc.splice(index, 0, ...content)
      pc!.insertAll(index, content);
    }
  }

  /**
   * Deletes elements starting from an index.
   *
   * @param {number} index Index at which to start deleting elements
   * @param {number} [length=1] The number of elements to remove. Defaults to 1.
   */
  void delete(int index, [int length = 1]) {
    final doc = this.doc;
    if (doc != null) {
      transact(doc, (transaction) {
        typeListDelete(transaction, this, index, length);
      });
    } else {
      // @ts-ignore _prelimContent is defined because this is not yet integrated
      this._prelimContent?.removeRange(index, index + length);
    }
  }

  /**
   * Transforms this YArray to a JavaScript Array.
   *
   * @return {Array<YXmlElement|YXmlText|YXmlHook>}
   */
  List<AbstractType> toArray () {
    return typeListToArray(this).cast();
  }

  /**
   * Appends content to this YArray.
   *
   * @param {Array<YXmlElement|YXmlText>} content Array of content to append.
   */
  void push (List<AbstractType> content) {
    this.insert(this.length, content);
  }

  /**
   * Prepends content to this YArray.
   *
   * @param {Array<YXmlElement|YXmlText>} content Array of content to prepend.
   */
  void unshift (List<AbstractType> content) {
    this.insert(0, content);
  }

  /**
   * Returns the i-th element from a YArray.
   *
   * @param {number} index The index of the element to return from the YArray
   * @return {YXmlElement|YXmlText}
   */
  AbstractType get(index) {
    return typeListGet(this, index);
  }

  /**
   * Returns a portion of this YXmlFragment into a JavaScript Array selected
   * from start to end (end not included).
   *
   * @param {number} [start]
   * @param {number} [end]
   * @return {Array<YXmlElement|YXmlText>}
   */
  List<AbstractType> slice([int start = 0, int? end]) {
    return typeListSlice(this, start, end ?? this.length).cast();
  }

  /**
   * Executes a provided function on once on every child element.
   *
   * @param {function(YXmlElement|YXmlText,number, typeof self):void} f A function to execute on every element of this YArray.
   */
  // forEach (f) {
  //   typeListForEach(this, f);
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
    encoder.writeTypeRef(YXmlFragmentRefID);
  }
}

/**
 * @param {UpdateDecoderV1 | UpdateDecoderV2} _decoder
 * @return {YXmlFragment}
 *
 * @private
 * @function
 */
YXmlFragment readYXmlFragment(AbstractUpdateDecoder _decoder) => YXmlFragment();
