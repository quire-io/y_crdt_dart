// import {
//   YEvent,
//   YXmlText, YXmlElement, YXmlFragment, Transaction // eslint-disable-line
// } from '../internals.js'

import 'package:y_crdt/src/types/abstract_type.dart';
import 'package:y_crdt/src/utils/y_event.dart';
import 'package:y_crdt/src/utils/transaction.dart';

/**
 * @extends YEvent<YXmlElement|YXmlText|YXmlFragment>
 * An Event that describes changes on a YXml Element or Yxml Fragment
 */
class YXmlEvent<T> extends YEvent {
  /**
   * @param {YXmlElement|YXmlText|YXmlFragment} target The target on which the event is created.
   * @param {Set<string|null>} subs The set of changed attributes. `null` is included if the
   *                   child list changed.
   * @param {Transaction} transaction The transaction instance with which the
   *                                  change was created.
   */
  YXmlEvent(AbstractType<YXmlEvent<T>> target, Set<String?> subs, Transaction transaction):
    super(target, transaction) {
    
    for (final sub in subs) {
      if (sub == null) {
        this.childListChanged = true;
      } else {
        this.attributesChanged.add(sub);
      }
    }
  }

  /**
   * Whether the children changed.
   * @type {Boolean}
   * @private
   */
  bool childListChanged = false;
  /**
   * Set of all changed attributes.
   * @type {Set<string>}
   */
  final attributesChanged = <String>{};
}