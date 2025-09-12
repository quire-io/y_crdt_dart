import 'dart:typed_data';
import 'dart:math' as math;

import 'package:y_crdt/src/lib0/binary.dart' as binary;
/**
 * @module encoding
 */
import "package:y_crdt/src/lib0/decoding.dart" as decoding;
import "package:y_crdt/src/lib0/encoding.dart" as encoding;
import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/gc.dart';
import 'package:y_crdt/src/structs/skip.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/doc.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/updates.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

/**
 * @param {UpdateEncoderV1 | UpdateEncoderV2} encoder
 * @param {List<GC|Item>} structs All structs by `client`
 * @param {number} client
 * @param {number} clock write structs starting with `ID(client,clock)`
 *
 * @function
 */
void _writeStructs(AbstractUpdateEncoder encoder, List<AbstractStruct> structs,
    int client, int clock) {
  // write first id
  clock = math.max(clock, structs[0].id.clock); // make sure the first id exists
  final startNewStructs = findIndexSS(structs, clock);
  // write # encoded structs
  encoding.writeVarUint(encoder.restEncoder, structs.length - startNewStructs);
  encoder.writeClient(client);
  encoding.writeVarUint(encoder.restEncoder, clock);
  final firstStruct = structs[startNewStructs];
  // write first struct with an offset
  firstStruct.write(encoder, clock - firstStruct.id.clock);
  for (var i = startNewStructs + 1; i < structs.length; i++) {
    structs[i].write(encoder, 0);
  }
}

/**
 * @param {AbstractUpdateEncoder} encoder
 * @param {StructStore} store
 * @param {Map<number,number>} _sm
 *
 * @private
 * @function
 */
void writeClientsStructs(
    AbstractUpdateEncoder encoder, StructStore store, Map<int, int> _sm) {
  // we filter all valid _sm entries into sm
  final sm = <int, int>{};
  _sm.forEach((client, clock) {
    // only write if new structs are available
    if (getState(store, client) > clock) {
      sm.set(client, clock);
    }
  });
  getStateVector(store).forEach((client, clock) {
    if (!_sm.containsKey(client)) {
      sm.set(client, 0);
    }
  });
  // write # states that were updated
  encoding.writeVarUint(encoder.restEncoder, sm.length);
  // Write items with higher client ids first
  // This heavily improves the conflict algorithm.
  final entries = sm.entries.toList();
  entries.sort((a, b) => b.key - a.key);
  entries.forEach((entry) {
    // @ts-ignore
    _writeStructs(
        encoder, store.clients.get(entry.key)!, entry.key, entry.value);
  });
}

class _ClietnRefs {
  int i;
  List<AbstractStruct> refs;
  _ClietnRefs({required this.i, required this.refs});
}


/**
 * @param {UpdateDecoderV1 | UpdateDecoderV2} decoder The decoder object to read data from.
 * @param {Doc} doc
 * @return {Map<number,List<GC|Item>>}
 *
 * @private
 * @function
 */
Map<int, _ClietnRefs> readClientsStructRefs(
    AbstractUpdateDecoder decoder, Doc doc) {
  final clientRefs = <int, _ClietnRefs>{};
  final numOfStateUpdates = decoding.readVarUint(decoder.restDecoder);
  for (var i = 0; i < numOfStateUpdates; i++) {
    final numberOfStructs = decoding.readVarUint(decoder.restDecoder);
    /**
     * @type {List<GC|Item>}
     */
    final refs = <AbstractStruct>[];
    final client = decoder.readClient();
    var clock = decoding.readVarUint(decoder.restDecoder);
    // final start = performance.now()
    clientRefs.set(client, _ClietnRefs(i: 0, refs: refs));
    for (var i = 0; i < numberOfStructs; i++) {
      final info = decoder.readInfo();
      switch (binary.BITS5 & info) {
        case 0: // GC
          final len = decoder.readLen();
          refs.add(GC(createID(client, clock), len));
          clock += len;
        case 10: // Skip Struct (nothing to apply)
          // @todo we could reduce the amount of checks by adding Skip struct to clientRefs so we know that something is missing.
          final len = decoding.readVarUint(decoder.restDecoder);
          refs.add(Skip(createID(client, clock), len));
          clock += len;
          break;
        default: // Item with content
          /**
           * The optimized implementation doesn't use any variables because inlining variables is faster.
           * Below a non-optimized version is shown that implements the basic algorithm with
           * a few comments
           */
          final cantCopyParentInfo = (info & (binary.BIT7 | binary.BIT8)) == 0;
          // If parent = null and neither left nor right are defined, then we know that `parent` is child of `y`
          // and we read the next string as parentYKey.
          // It indicates how we store/retrieve parent from `y.share`
          // @type {string|null}
          final struct = Item(
            createID(client, clock),
            null, // leftd
            (info & binary.BIT8) == binary.BIT8
                ? decoder.readLeftID()
                : null, // origin
            null, // right
            (info & binary.BIT7) == binary.BIT7
                ? decoder.readRightID()
                : null, // right origin
            cantCopyParentInfo
                ? decoder.readParentInfo()
                    ? doc.get(decoder.readString())
                    : decoder.readLeftID()
                : null, // parent
            cantCopyParentInfo && (info & binary.BIT6) == binary.BIT6
                ? decoder.readString()
                : null, // parentSub
            readItemContent(decoder, info) as AbstractContent // item content
            );
        /* A non-optimized implementation of the above algorithm:

        // The item that was originally to the left of this item.
        const origin = (info & binary.BIT8) == binary.BIT8 ? decoder.readLeftID() : null
        // The item that was originally to the right of this item.
        const rightOrigin = (info & binary.BIT7) == binary.BIT7 ? decoder.readRightID() : null
        const cantCopyParentInfo = (info & (binary.BIT7 | binary.BIT8)) == 0
        const hasParentYKey = cantCopyParentInfo ? decoder.readParentInfo() : false
        // If parent = null and neither left nor right are defined, then we know that `parent` is child of `y`
        // and we read the next string as parentYKey.
        // It indicates how we store/retrieve parent from `y.share`
        // @type {string|null}
        const parentYKey = cantCopyParentInfo && hasParentYKey ? decoder.readString() : null

        const struct = new Item(
          createID(client, clock),
          null, // left
          origin, // origin
          null, // right
          rightOrigin, // right origin
          cantCopyParentInfo && !hasParentYKey ? decoder.readLeftID() : (parentYKey != null ? doc.get(parentYKey) : null), // parent
          cantCopyParentInfo && (info & binary.BIT6) == binary.BIT6 ? decoder.readString() : null, // parentSub
          readItemContent(decoder, info) // item content
        )
        */
        refs.add(struct);
        clock += struct.length;
      }
    }
    // console.log('time to read: ', performance.now() - start) // @todo remove
  }
  return clientRefs;
}

/**
 * Resume computing structs generated by struct readers.
 *
 * While there is something to do, we integrate structs in this order
 * 1. top element on stack, if stack is not empty
 * 2. next element from current struct reader (if empty, use next struct reader)
 *
 * If struct causally depends on another struct (ref.missing), we put next reader of
 * `ref.id.client` on top of stack.
 *
 * At some point we find a struct that has no causal dependencies,
 * then we start emptying the stack.
 *
 * It is not possible to have circles: i.e. struct1 (from client1) depends on struct2 (from client2)
 * depends on struct3 (from client1). Therefore the max stack size is eqaul to `structReaders.length`.
 *
 * This method is implemented in a way so that we can resume computation if this update
 * causally depends on another update.
 *
 * @param {Transaction} transaction
 * @param {StructStore} store
 * @param {Map<number, { i: number, refs: (GC | Item)[] }>} clientsStructRefs
 * @return { null | { update: Uint8Array, missing: Map<number,number> } }
 *
 * @private
 * @function
 */
PendingStructs? integrateStructs(Transaction transaction, StructStore store, Map<int, _ClietnRefs> clientsStructRefs) {
  /**
   * @type {Array<Item | GC>}
   */
  final stack = <AbstractStruct>[];
  // sort them so that we take the higher id first, in case of conflicts the lower id will probably not conflict with the id from the higher user.
  var clientsStructRefsIds = clientsStructRefs.keys.toList();
  clientsStructRefsIds.sort((a, b) => a - b);
  if (clientsStructRefsIds.length == 0) {
    return null;
  }
  _ClietnRefs? getNextStructTarget() {
    if (clientsStructRefsIds.length == 0) {
      return null;
    }
    var nextStructsTarget = /** @type {{i:number,refs:Array<GC|Item>}} */ (clientsStructRefs.get(
      clientsStructRefsIds[clientsStructRefsIds.length - 1]));
    while (nextStructsTarget != null 
        && nextStructsTarget.refs.length == nextStructsTarget.i) {
      clientsStructRefsIds.removeLast();
      if (clientsStructRefsIds.length > 0) {
        nextStructsTarget = /** @type {{i:number,refs:Array<GC|Item>}} */ (clientsStructRefs.get(
          clientsStructRefsIds[clientsStructRefsIds.length - 1]));
      } else {
        return null;
      }
    }
    return nextStructsTarget;
  }
  var curStructsTarget = getNextStructTarget();
  if (curStructsTarget == null) {
    return null;
  }

  /**
   * @type {StructStore}
   */
  final restStructs = StructStore();
  final missingSV = <int, int>{};
  /**
   * @param {number} client
   * @param {number} clock
   */
  void updateMissingSv(int client, int clock) {
    final mclock = missingSV.get(client);
    if (mclock == null || mclock > clock) {
      missingSV.set(client, clock);
    }
  }
  /**
   * @type {GC|Item}
   */
  var stackHead = /** @type {any} */ (curStructsTarget).refs[/** @type {any} */ (curStructsTarget).i++];
  // caching the state because it is used very often
  final state = <int, int>{};

  addStackToRestSS(){
    for (final item in stack) {
      final client = item.id.client;
      final inapplicableItems = clientsStructRefs.get(client);
      if (inapplicableItems != null) {
        // decrement because we weren't able to apply previous operation
        inapplicableItems.i--;
        restStructs.clients.set(client, inapplicableItems.refs.sublist(inapplicableItems.i));
        clientsStructRefs.remove(client);
        inapplicableItems.i = 0;
        inapplicableItems.refs = [];
      } else {
        // item was the last item on clientsStructRefs and the field was already cleared. Add item to restStructs and continue
        restStructs.clients.set(client, [item]);
      }
      // remove client from clientsStructRefsIds to prevent users from applying the same update again
      clientsStructRefsIds = clientsStructRefsIds.where((c) => c != client).toList();
    }
    stack.length = 0;
  }

  // iterate over all struct readers until we are done
  while (true) {
    if (stackHead is! Skip) {
      final localClock = state.putIfAbsent(stackHead.id.client, () => getState(store, stackHead.id.client));
      final offset = localClock - stackHead.id.clock;
      if (offset < 0) {
        // update from the same client is missing
        stack.add(stackHead);
        updateMissingSv(stackHead.id.client, stackHead.id.clock - 1);
        // hid a dead wall, add all items from stack to restSS
        addStackToRestSS();
      } else if (stackHead is Item) {
        final missing = stackHead.getMissing(transaction, store);
        if (missing != null) {
          stack.add(stackHead);
          // get the struct reader that has the missing struct
          /**
           * @type {{ refs: Array<GC|Item>, i: number }}
           */
          final structRefs = clientsStructRefs.get(/** @type {number} */ (missing)) 
            ?? _ClietnRefs(refs: [], i: 0);
          if (structRefs.refs.length == structRefs.i) {
            // This update message causally depends on another update message that doesn't exist yet
            updateMissingSv(/** @type {number} */ (missing), getState(store, missing));
            addStackToRestSS();
          } else {
            stackHead = structRefs.refs[structRefs.i++];
            continue;
          }
        } else if (offset == 0 || offset < stackHead.length) {
          // all fine, apply the stackhead
          stackHead.integrate(transaction, offset);
          state.set(stackHead.id.client, stackHead.id.clock + stackHead.length);
        }
      }
    }
    // iterate to next stackHead
    if (stack.length > 0) {
      stackHead = /** @type {GC|Item} */ stack.removeLast();
    } else if (curStructsTarget != null && curStructsTarget.i < curStructsTarget.refs.length) {
      stackHead = /** @type {GC|Item} */ (curStructsTarget.refs[curStructsTarget.i++]);
    } else {
      curStructsTarget = getNextStructTarget();
      if (curStructsTarget == null) {
        // we are done!
        break;
      } else {
        stackHead = /** @type {GC|Item} */ (curStructsTarget.refs[curStructsTarget.i++]);
      }
    }
  }
  if (restStructs.clients.isNotEmpty) {
    final encoder = UpdateEncoderV2();
    writeClientsStructs(encoder, restStructs, {});
    // write empty deleteset
    // writeDeleteSet(encoder, new DeleteSet())
    encoding.writeVarUint(encoder.restEncoder, 0); // => no need for an extra function call, just write 0 deletes
    return PendingStructs(missing: missingSV, update: encoder.toUint8Array());
  }
  return null;
}

/**
 * @param {AbstractUpdateEncoder} encoder
 * @param {Transaction} transaction
 *
 * @private
 * @function
 */
void writeStructsFromTransaction(
        AbstractUpdateEncoder encoder, Transaction transaction) =>
    writeClientsStructs(
        encoder, transaction.doc.store, transaction.beforeState);

/**
 * Read and apply a document update.
 *
 * This function has the same effect as `applyUpdate` but accepts an decoder.
 *
 * @param {decoding.Decoder} decoder
 * @param {Doc} ydoc
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 * @param {AbstractUpdateDecoder} [structDecoder]
 *
 * @function
 */
void readUpdateV2(decoding.Decoder decoder, Doc ydoc, dynamic transactionOrigin,
    AbstractUpdateDecoder? structDecoder) {
  structDecoder ??= UpdateDecoderV2(decoder);
  transact(ydoc, (transaction) {
    // readStructs(_structDecoder, transaction, ydoc.store);
    // readAndApplyDeleteSet(_structDecoder, transaction, ydoc.store);
    // force that transaction.local is set to non-local
    transaction.local = false;
    var retry = false;
    final doc = transaction.doc;
    final store = doc.store;
    // let start = performance.now()
    final ss = readClientsStructRefs(structDecoder!, doc);
    // console.log('time to read structs: ', performance.now() - start) // @todo remove
    // start = performance.now()
    // console.log('time to merge: ', performance.now() - start) // @todo remove
    // start = performance.now()
    final restStructs = integrateStructs(transaction, store, ss);
    final pending = store.pendingStructs;
    if (pending != null) {
      // check if we can apply something
      //for (const [client, clock] of pending.missing) {
      for (final en in pending.missing.entries) {
        if (en.value < getState(store, en.key)) {
          retry = true;
          break;
        }
      }
      if (restStructs != null) {
        // merge restStructs into store.pending
        //for (const [client, clock] of restStructs.missing) {
        for (final en in restStructs.missing.entries) {
          final client = en.key,
            clock = en.value,
            mclock = pending.missing.get(client);
          if (mclock == null || mclock > clock) {
            pending.missing.set(client, clock);
          }
        }
        pending.update = mergeUpdatesV2([pending.update, restStructs.update]);
      }
    } else {
      store.pendingStructs = restStructs;
    }
    // console.log('time to integrate: ', performance.now() - start) // @todo remove
    // start = performance.now()
    final dsRest = readAndApplyDeleteSet(structDecoder, transaction, store);
    if (store.pendingDs != null) {
      // @todo we could make a lower-bound state-vector check as we do above
      final pendingDSUpdate = UpdateDecoderV2(decoding.createDecoder(store.pendingDs!));
      decoding.readVarUint(pendingDSUpdate.restDecoder); // read 0 structs, because we only encode deletes in pendingdsupdate
      final dsRest2 = readAndApplyDeleteSet(pendingDSUpdate, transaction, store);
      if (dsRest != null && dsRest2 != null) {
        // case 1: ds1 != null && ds2 != null
        store.pendingDs = mergeUpdatesV2([dsRest, dsRest2]);
      } else {
        // case 2: ds1 != null
        // case 3: ds2 != null
        // case 4: ds1 == null && ds2 == null
        store.pendingDs = dsRest ?? dsRest2;
      }
    } else {
      // Either dsRest == null && pendingDs == null OR dsRest != null
      store.pendingDs = dsRest;
    }
    // console.log('time to cleanup: ', performance.now() - start) // @todo remove
    // start = performance.now()

    // console.log('time to resume delete readers: ', performance.now() - start) // @todo remove
    // start = performance.now()
    if (retry) {
      final update = /** @type {{update: Uint8Array}} */ (store.pendingStructs)!.update;
      store.pendingStructs = null;
      applyUpdateV2(transaction.doc, update);
    }
  }, transactionOrigin, false);
}

/**
 * Read and apply a document update.
 *
 * This function has the same effect as `applyUpdate` but accepts an decoder.
 *
 * @param {decoding.Decoder} decoder
 * @param {Doc} ydoc
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 *
 * @function
 */
void readUpdate(
        decoding.Decoder decoder, Doc ydoc, dynamic transactionOrigin) =>
    readUpdateV2(
        decoder, ydoc, transactionOrigin, UpdateDecoderV1(decoder));

/**
 * Apply a document update created by, for example, `y.on('update', update => ..)` or `update = encodeStateAsUpdate()`.
 *
 * This function has the same effect as `readUpdate` but accepts an Uint8Array instead of a Decoder.
 *
 * @param {Doc} ydoc
 * @param {Uint8Array} update
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 * @param {typeof UpdateDecoderV1 | typeof UpdateDecoderV2} [YDecoder]
 *
 * @function
 */
void applyUpdateV2(
  Doc ydoc,
  Uint8List update, [
  dynamic transactionOrigin, 
  AbstractUpdateDecoder Function(decoding.Decoder decoder)? YDecoder,
]) {
  final _YDecoder = YDecoder ?? UpdateDecoderV2.new;
  final decoder = decoding.createDecoder(update);
  readUpdateV2(decoder, ydoc, transactionOrigin, _YDecoder(decoder));
}

/**
 * Apply a document update created by, for example, `y.on('update', update => ..)` or `update = encodeStateAsUpdate()`.
 *
 * This function has the same effect as `readUpdate` but accepts an Uint8Array instead of a Decoder.
 *
 * @param {Doc} ydoc
 * @param {Uint8Array} update
 * @param {any} [transactionOrigin] This will be stored on `transaction.origin` and `.on('update', (update, origin))`
 *
 * @function
 */
void applyUpdate(Doc ydoc, Uint8List update, dynamic transactionOrigin) =>
    applyUpdateV2(ydoc, update, transactionOrigin, UpdateDecoderV1.new);

/**
 * Write all the document as a single update message. If you specify the state of the remote client (`targetStateVector`) it will
 * only write the operations that are missing.
 *
 * @param {AbstractUpdateEncoder} encoder
 * @param {Doc} doc
 * @param {Map<number,number>} [targetStateVector] The state of the target that receives the update. Leave empty to write all known structs
 *
 * @function
 */
void writeStateAsUpdate(AbstractUpdateEncoder encoder, Doc doc,
    [Map<int, int> targetStateVector = const <int, int>{}]) {
  writeClientsStructs(encoder, doc.store, targetStateVector);
  writeDeleteSet(encoder, createDeleteSetFromStructStore(doc.store));
}

/**
 * Write all the document as a single update message that can be applied on the remote document. If you specify the state of the remote client (`targetState`) it will
 * only write the operations that are missing.
 *
 * Use `writeStateAsUpdate` instead if you are working with lib0/encoding.js#Encoder
 *
 * @param {Doc} doc
 * @param {Uint8Array} [encodedTargetStateVector] The state of the target that receives the update. Leave empty to write all known structs
 * @param {AbstractUpdateEncoder} [encoder]
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateAsUpdateV2(
  Doc doc,
  Uint8List? encodedTargetStateVector, [
  AbstractUpdateEncoder? encoder,
]) {
  encodedTargetStateVector ??= Uint8List.fromList([0]);
  encoder ??= UpdateEncoderV2();

  final targetStateVector = decodeStateVector(encodedTargetStateVector);
  writeStateAsUpdate(encoder, doc, targetStateVector);
  final updates = [encoder.toUint8Array()];
  // also add the pending updates (if there are any)
  if (doc.store.pendingDs != null) {
    updates.add(doc.store.pendingDs!);
  }
  if (doc.store.pendingStructs case PendingStructs pendingStructs) {
    updates.add(diffUpdateV2(pendingStructs.update, encodedTargetStateVector));
  }
  if (updates.length > 1) {
    if (encoder is UpdateEncoderV1) {
      var i = 0;
      return mergeUpdates(updates.map((update) {
        final value = i == 0 ? update : convertUpdateFormatV2ToV1(update);
        i++;
        return value;
      }));
    } else if (encoder is UpdateEncoderV2) {
      return mergeUpdatesV2(updates);
    }
  }
  return updates[0];
}

/**
 * Write all the document as a single update message that can be applied on the remote document. If you specify the state of the remote client (`targetState`) it will
 * only write the operations that are missing.
 *
 * Use `writeStateAsUpdate` instead if you are working with lib0/encoding.js#Encoder
 *
 * @param {Doc} doc
 * @param {Uint8Array} [encodedTargetStateVector] The state of the target that receives the update. Leave empty to write all known structs
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateAsUpdate(Doc doc, Uint8List? encodedTargetStateVector) =>
    encodeStateAsUpdateV2(
        doc, encodedTargetStateVector, UpdateEncoderV1());

/**
 * Read state vector from Decoder and return as Map
 *
 * @param {AbstractDSDecoder} decoder
 * @return {Map<number,number>} Maps `client` to the number next expected `clock` from that client.
 *
 * @function
 */
Map<int, int> readStateVector(AbstractDSDecoder decoder) {
  final ss = <int, int>{};
  final ssLength = decoding.readVarUint(decoder.restDecoder);
  for (var i = 0; i < ssLength; i++) {
    final client = decoding.readVarUint(decoder.restDecoder);
    final clock = decoding.readVarUint(decoder.restDecoder);
    ss.set(client, clock);
  }
  return ss;
}

/**
 * Read decodedState and return State as Map.
 *
 * @param {Uint8Array} decodedState
 * @return {Map<number,number>} Maps `client` to the number next expected `clock` from that client.
 *
 * @function
 */
// Map<int, int> decodeStateVectorV2(Uint8List decodedState) =>
//     readStateVector(DSDecoderV2(decoding.createDecoder(decodedState)));

/**
 * Read decodedState and return State as Map.
 *
 * @param {Uint8Array} decodedState
 * @return {Map<number,number>} Maps `client` to the number next expected `clock` from that client.
 *
 * @function
 */
Map<int, int> decodeStateVector(Uint8List decodedState) =>
    readStateVector(DSDecoderV1(decoding.createDecoder(decodedState)));

/**
 * @param {AbstractDSEncoder} encoder
 * @param {Map<number,number>} sv
 * @function
 */
AbstractDSEncoder writeStateVector(
    AbstractDSEncoder encoder, Map<int, int> sv) {
  encoding.writeVarUint(encoder.restEncoder, sv.length);
  final list = sv.entries.toList();
  list.sort((a, b) => b.key - a.key);
  for (final en in list) {
    encoding.writeVarUint(encoder.restEncoder,
        en.key); // @todo use a special client decoder that is based on mapping
    encoding.writeVarUint(encoder.restEncoder, en.value);
  }
  return encoder;
}

/**
 * @param {AbstractDSEncoder} encoder
 * @param {Doc} doc
 *
 * @function
 */
void writeDocumentStateVector(AbstractDSEncoder encoder, Doc doc) =>
    writeStateVector(encoder, getStateVector(doc.store));

/**
 * Encode State as Uint8Array.
 *
 * @param {Doc|Map<number,number>} doc
 * @param {AbstractDSEncoder} [encoder]
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateVectorV2(doc, [AbstractDSEncoder? encoder]) {
  final _encoder = encoder ?? DSEncoderV2();
  if (doc case Map<int, int> map) {
    writeStateVector(_encoder, map);
  } else {
    writeDocumentStateVector(_encoder, doc as Doc);
  }
  return _encoder.toUint8Array();
}

/**
 * Encode State as Uint8Array.
 *
 * @param {Doc} doc
 * @return {Uint8Array}
 *
 * @function
 */
Uint8List encodeStateVector(Doc doc) =>
    encodeStateVectorV2(doc, DSEncoderV1());
