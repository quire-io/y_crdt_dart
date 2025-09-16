// import * as binary from 'lib0/binary'
// import * as decoding from 'lib0/decoding'
// import * as encoding from 'lib0/encoding'
// import * as error from 'lib0/error'
// import * as f from 'lib0/function'
// import * as logging from 'lib0/logging'
// import * as map from 'lib0/map'
// import * as math from 'lib0/math'
// import * as string from 'lib0/string'

import 'dart:typed_data';
import 'dart:math' as math;

import 'package:y_crdt/src/lib0/binary.dart' as binary;

import "package:y_crdt/src/lib0/decoding.dart" as decoding;
import "package:y_crdt/src/lib0/encoding.dart" as encoding;
import "package:y_crdt/src/lib0/function.dart" as f;
import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/structs/gc.dart';
import 'package:y_crdt/src/structs/skip.dart';
import 'package:y_crdt/src/structs/item.dart';
import 'package:y_crdt/src/structs/content_any.dart';
import 'package:y_crdt/src/structs/content_binary.dart';
import 'package:y_crdt/src/structs/content_deleted.dart';
import 'package:y_crdt/src/structs/content_doc.dart';
import 'package:y_crdt/src/structs/content_embed.dart';
import 'package:y_crdt/src/structs/content_format.dart';
import 'package:y_crdt/src/structs/content_json.dart';
import 'package:y_crdt/src/structs/content_string.dart';
import 'package:y_crdt/src/structs/content_type.dart';
import 'package:y_crdt/src/utils/delete_set.dart';
import 'package:y_crdt/src/utils/encoding.dart';
import 'package:y_crdt/src/utils/id.dart';
import 'package:y_crdt/src/utils/update_decoder.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';
import 'package:y_crdt/src/y_crdt_base.dart';

// import {
//   ContentAny,
//   ContentBinary,
//   ContentDeleted,
//   ContentDoc,
//   ContentEmbed,
//   ContentFormat,
//   ContentJSON,
//   ContentString,
//   ContentType,
//   createID,
//   decodeStateVector,
//   DSEncoderV1,
//   DSEncoderV2,
//   GC,
//   Item,
//   mergeDeleteSets,
//   readDeleteSet,
//   readItemContent,
//   Skip,
//   UpdateDecoderV1,
//   UpdateDecoderV2,
//   UpdateEncoderV1,
//   UpdateEncoderV2,
//   writeDeleteSet,
//   YXmlElement,
//   YXmlHook
// } from '../internals.js'

/**
 * @param {UpdateDecoderV1 | UpdateDecoderV2} decoder
 */
Iterable<AbstractStruct> lazyStructReaderGenerator (AbstractUpdateDecoder decoder) sync* {
  final numOfStateUpdates = decoding.readVarUint(decoder.restDecoder);
  for (var i = 0; i < numOfStateUpdates; i++) {
    final numberOfStructs = decoding.readVarUint(decoder.restDecoder);
    final client = decoder.readClient();
    var clock = decoding.readVarUint(decoder.restDecoder);
    for (var i = 0; i < numberOfStructs; i++) {
      final info = decoder.readInfo();
      // @todo use switch instead of ifs
      if (info == 10) {
        final len = decoding.readVarUint(decoder.restDecoder);
        yield Skip(createID(client, clock), len);
        clock += len;
      } else if ((binary.BITS5 & info) != 0) {
        final cantCopyParentInfo = (info & (binary.BIT7 | binary.BIT8)) == 0;
        // If parent = null and neither left nor right are defined, then we know that `parent` is child of `y`
        // and we read the next string as parentYKey.
        // It indicates how we store/retrieve parent from `y.share`
        // @type {string|null}
        final struct = Item(
          createID(client, clock),
          null, // left
          (info & binary.BIT8) == binary.BIT8 ? decoder.readLeftID() : null, // origin
          null, // right
          (info & binary.BIT7) == binary.BIT7 ? decoder.readRightID() : null, // right origin
          // @ts-ignore Force writing a string here.
          cantCopyParentInfo ? (decoder.readParentInfo() ? decoder.readString() : decoder.readLeftID()) : null, // parent
          cantCopyParentInfo && (info & binary.BIT6) == binary.BIT6 ? decoder.readString() : null, // parentSub
          readItemContent(decoder, info) // item content
        );
        yield struct;
        clock += struct.length;
      } else {
        final len = decoder.readLen();
        yield GC(createID(client, clock), len);
        clock += len;
      }
    }
  }
}

class LazyStructReader {
  /**
   * @param {UpdateDecoderV1 | UpdateDecoderV2} decoder
   * @param {boolean} filterSkips
   */
  LazyStructReader (AbstractUpdateDecoder decoder, this.filterSkips):
    this.gen = lazyStructReaderGenerator(decoder).iterator {
    this.next();
  }

  final Iterator<AbstractStruct> gen;

  bool done = false;

  final bool filterSkips;

  /**
   * @type {null | Item | Skip | GC}
   */
  AbstractStruct? curr;

  /**
   * @return {Item | GC | Skip |null}
   */
  AbstractStruct? next () {
    // ignore "Skip" structs
    final it = this.gen;
    do {
      this.curr = it.moveNext() ? it.current : null;
    } while (this.filterSkips && this.curr != null && this.curr is Skip);
    return this.curr;
  }
}

/**
 * @param {Uint8Array} update
 *
 */
void logUpdate(Uint8List update) => logUpdateV2(update, 
  (decoder) => UpdateDecoderV1(decoder));

/**
 * @param {Uint8Array} update
 * @param {typeof UpdateDecoderV2 | typeof UpdateDecoderV1} [YDecoder]
 *
 */
void logUpdateV2(Uint8List update, [AbstractUpdateDecoder YDecoder(decoding.Decoder decoder)?]) {
  YDecoder ??= UpdateDecoderV2.new;
  final structs = [];
  final updateDecoder = YDecoder(decoding.createDecoder(update));
  final lazyDecoder = LazyStructReader(updateDecoder, false);
  for (var curr = lazyDecoder.curr; curr != null; curr = lazyDecoder.next()) {
    structs.add(curr);
  }
  // logging.print('Structs: ', structs)
  readDeleteSet(updateDecoder);
  // logging.print('DeleteSet: ', ds)
}

/**
 * @param {Uint8Array} update
 *
 */
(List<AbstractStruct>, DeleteSet) decodeUpdate(Uint8List update) 
  => decodeUpdateV2(update, (decoder) => UpdateDecoderV1(decoder));

/**
 * @param {Uint8Array} update
 * @param {typeof UpdateDecoderV2 | typeof UpdateDecoderV1} [YDecoder]
 *
 */
(List<AbstractStruct>, DeleteSet) decodeUpdateV2(Uint8List update, 
    AbstractUpdateDecoder YDecoder(decoding.Decoder decoder)?) {
  YDecoder ??= UpdateDecoderV2.new;
  final structs = <AbstractStruct>[];
  final updateDecoder = YDecoder(decoding.createDecoder(update));
  final lazyDecoder = LazyStructReader(updateDecoder, false);
  for (var curr = lazyDecoder.curr; curr != null; curr = lazyDecoder.next()) {
    structs.add(curr);
  }
  return (structs, readDeleteSet(updateDecoder));
}

class PartStructs {
 final int written;
  final Uint8List restEncoder;
  
  PartStructs(this.written, this.restEncoder); 
}

class LazyStructWriter {
  /**
   * @param {UpdateEncoderV1 | UpdateEncoderV2} encoder
   */
  LazyStructWriter(this.encoder);

  int currClient = 0,
    startClock = 0,
    written = 0;

  final AbstractUpdateEncoder encoder;
  
  /**
     * We want to write operations lazily, but also we need to know beforehand how many operations we want to write for each client.
     *
     * This kind of meta-information (#clients, #structs-per-client-written) is written to the restEncoder.
     *
     * We fragment the restEncoder and store a slice of it per-client until we know how many clients there are.
     * When we flush (toUint8Array) we write the restEncoder using the fragments and the meta-information.
     *
     * @type {Array<{ written: number, restEncoder: Uint8Array }>}
     */
  final clientStructs = <PartStructs>[];
}

/**
 * @param {Array<Uint8Array>} updates
 * @return {Uint8Array}
 */
Uint8List mergeUpdates(Iterable<Uint8List> updates) => mergeUpdatesV2(
    updates, UpdateDecoderV1.new, UpdateEncoderV1.new);

/**
 * @param {Uint8Array} update
 * @param {typeof DSEncoderV1 | typeof DSEncoderV2} YEncoder
 * @param {typeof UpdateDecoderV1 | typeof UpdateDecoderV2} YDecoder
 * @return {Uint8Array}
 */
Uint8List encodeStateVectorFromUpdateV2(Uint8List update, [
    AbstractDSEncoder YEncoder()?,
    AbstractUpdateDecoder YDecoder(decoding.Decoder decoder)?,]) {
  YDecoder ??= UpdateDecoderV2.new;
  YEncoder ??= UpdateEncoderV2.new;

  final encoder = YEncoder();
  final updateDecoder = LazyStructReader(YDecoder(decoding.createDecoder(update)), false);
  var curr = updateDecoder.curr;
  if (curr != null) {
    var size = 0;
    var currClient = curr.id.client;
    var stopCounting = curr.id.clock != 0; // must start at 0
    var currClock = stopCounting ? 0 : curr.id.clock + curr.length;
    for (; curr != null; curr = updateDecoder.next()) {
      if (currClient != curr.id.client) {
        if (currClock != 0) {
          size++;
          // We found a new client
          // write what we have to the encoder
          encoding.writeVarUint(encoder.restEncoder, currClient);
          encoding.writeVarUint(encoder.restEncoder, currClock);
        }
        currClient = curr.id.client;
        currClock = 0;
        stopCounting = curr.id.clock != 0;
      }
      // we ignore skips
      if (curr is Skip) {
        stopCounting = true;
      }
      if (!stopCounting) {
        currClock = curr.id.clock + curr.length;
      }
    }
    // write what we have
    if (currClock != 0) {
      size++;
      encoding.writeVarUint(encoder.restEncoder, currClient);
      encoding.writeVarUint(encoder.restEncoder, currClock);
    }
    // prepend the size of the state vector
    final enc = encoding.createEncoder();
    encoding.writeVarUint(enc, size);
    encoding.writeBinaryEncoder(enc, encoder.restEncoder);
    encoder.restEncoder = enc;
    return encoder.toUint8Array();
  } else {
    encoding.writeVarUint(encoder.restEncoder, 0);
    return encoder.toUint8Array();
  }
}

/**
 * @param {Uint8Array} update
 * @return {Uint8Array}
 */
Uint8List encodeStateVectorFromUpdate (Uint8List update) 
  => encodeStateVectorFromUpdateV2(update, DSEncoderV1.new, UpdateDecoderV1.new);

/**
 * @param {Uint8Array} update
 * @param {typeof UpdateDecoderV1 | typeof UpdateDecoderV2} YDecoder
 * @return {{ from: Map<number,number>, to: Map<number,number> }}
 */
(Map<int, int>, Map<int, int>) parseUpdateMetaV2(Uint8List update, 
    [AbstractUpdateDecoder YDecoder(decoding.Decoder decoder)?]) {
  YDecoder ??= UpdateDecoderV2.new;
  /**
   * @type {Map<number, number>}
   */
  final from = <int, int>{};
  /**
   * @type {Map<number, number>}
   */
  final to = <int, int>{};
  final updateDecoder = LazyStructReader(YDecoder(decoding.createDecoder(update)), false);
  var curr = updateDecoder.curr;
  if (curr != null) {
    var currClient = curr.id.client;
    var currClock = curr.id.clock;
    // write the beginning to `from`
    from.set(currClient, currClock);
    for (; curr != null; curr = updateDecoder.next()) {
      if (currClient != curr.id.client) {
        // We found a new client
        // write the end to `to`
        to.set(currClient, currClock);
        // write the beginning to `from`
        from.set(curr.id.client, curr.id.clock);
        // update currClient
        currClient = curr.id.client;
      }
      currClock = curr.id.clock + curr.length;
    }
    // write the end to `to`
    to.set(currClient, currClock);
  }
  return (from, to);
}

/**
 * @param {Uint8Array} update
 * @return {{ from: Map<number,number>, to: Map<number,number> }}
 */
(Map<int, int>, Map<int, int>) parseUpdateMeta(Uint8List update) 
  => parseUpdateMetaV2(update, UpdateDecoderV1.new);

/**
 * This method is intended to slice any kind of struct and retrieve the right part.
 * It does not handle side-effects, so it should only be used by the lazy-encoder.
 *
 * @param {Item | GC | Skip} left
 * @param {number} diff
 * @return {Item | GC}
 */
AbstractStruct sliceStruct(AbstractStruct left, int diff) {
  if (left is GC) {
    return GC(createID(left.id.client, left.id.clock + diff), left.length - diff);
  } else if (left is Skip) {
    return Skip(createID(left.id.client, left.id.clock + diff), left.length - diff);
  } else {
    var leftItem = /** @type {Item} */ (left as Item);
    final client = leftItem.id.client;
    final clock = leftItem.id.clock;
    return Item(
      createID(client, clock + diff),
      null,
      createID(client, clock + diff - 1),
      null,
      leftItem.rightOrigin,
      leftItem.parent,
      leftItem.parentSub,
      leftItem.content.splice(diff)
    );
  }
}

class _Write {
  final AbstractStruct struct;
  final int offset;
  _Write(this.struct, this.offset);
}

/**
 *
 * This function works similarly to `readUpdateV2`.
 *
 * @param {Array<Uint8Array>} updates
 * @param {typeof UpdateDecoderV1 | typeof UpdateDecoderV2} [YDecoder]
 * @param {typeof UpdateEncoderV1 | typeof UpdateEncoderV2} [YEncoder]
 * @return {Uint8Array}
 */
Uint8List mergeUpdatesV2(Iterable<Uint8List> updates, [
    AbstractUpdateDecoder YDecoder(decoding.Decoder decoder)?,
    AbstractUpdateEncoder YEncoder()?]) {
  YDecoder ??= UpdateDecoderV2.new;
  YEncoder ??= UpdateEncoderV2.new;
  if (updates.length == 1) {
    return updates.first;
  }
  final updateDecoders = updates.map((update) => YDecoder!(decoding.createDecoder(update))).toList();
  var lazyStructDecoders = updateDecoders.map((decoder) => LazyStructReader(decoder, true)).toList();

  /**
   * @todo we don't need offset because we always slice before
   * @type {null | { struct: Item | GC | Skip, offset: number }}
   */
  _Write? currWrite;

  final updateEncoder = YEncoder();
  // write structs lazily
  final lazyStructEncoder = LazyStructWriter(updateEncoder);

  // Note: We need to ensure that all lazyStructDecoders are fully consumed
  // Note: Should merge document updates whenever possible - even from different updates
  // Note: Should handle that some operations cannot be applied yet ()

  while (true) {
    // Write higher clients first ⇒ sort by clientID & clock and remove decoders without content
    lazyStructDecoders = lazyStructDecoders.where((dec) => dec.curr != null).toList();
    lazyStructDecoders.sort(
      /** @type {function(any,any):number} */ (dec1, dec2) {
        if (dec1.curr!.id.client == dec2.curr!.id.client) {
          final clockDiff = dec1.curr!.id.clock - dec2.curr!.id.clock;
          if (clockDiff == 0) {
            // @todo remove references to skip since the structDecoders must filter Skips.
            return dec1.curr.runtimeType == dec2.curr.runtimeType
              ? 0
              : dec1.curr is Skip ? 1 : -1; // we are filtering skips anyway.
          } else {
            return clockDiff;
          }
        } else {
          return dec2.curr!.id.client - dec1.curr!.id.client;
        }
      }
    );
    if (lazyStructDecoders.length == 0) {
      break;
    }
    final currDecoder = lazyStructDecoders[0];
    // write from currDecoder until the next operation is from another client or if filler-struct
    // then we need to reorder the decoders and find the next operation to write
    final firstClient = /** @type {Item | GC} */ (currDecoder.curr)!.id.client;

    if (currWrite != null) {
      var curr = /** @type {Item | GC | null} */ (currDecoder.curr);
      var iterated = false;

      // iterate until we find something that we haven't written already
      // remember: first the high client-ids are written
      while (curr != null && curr.id.clock + curr.length <= currWrite.struct.id.clock + currWrite.struct.length && curr.id.client >= currWrite.struct.id.client) {
        curr = currDecoder.next();
        iterated = true;
      }
      if (
        curr == null || // current decoder is empty
        curr.id.client != firstClient || // check whether there is another decoder that has has updates from `firstClient`
        (iterated && curr.id.clock > currWrite.struct.id.clock + currWrite.struct.length) // the above while loop was used and we are potentially missing updates
      ) {
        continue;
      }

      if (firstClient != currWrite.struct.id.client) {
        writeStructToLazyStructWriter(lazyStructEncoder, currWrite.struct, currWrite.offset);
        currWrite = _Write(curr, 0);
        currDecoder.next();
      } else {
        if (currWrite.struct.id.clock + currWrite.struct.length < curr.id.clock) {
          // @todo write currStruct & set currStruct = Skip(clock = currStruct.id.clock + currStruct.length, length = curr.id.clock - self.clock)
          if (currWrite.struct is Skip) {
            // extend existing skip
            currWrite.struct.length = curr.id.clock + curr.length - currWrite.struct.id.clock;
          } else {
            writeStructToLazyStructWriter(lazyStructEncoder, currWrite.struct, currWrite.offset);
            final diff = curr.id.clock - currWrite.struct.id.clock - currWrite.struct.length;
            /**
             * @type {Skip}
             */
            final struct = Skip(createID(firstClient, currWrite.struct.id.clock + currWrite.struct.length), diff);
            currWrite = _Write(struct, 0);
          }
        } else { // if (currWrite.struct.id.clock + currWrite.struct.length >= curr.id.clock) {
          final diff = currWrite.struct.id.clock + currWrite.struct.length - curr.id.clock;
          if (diff > 0) {
            if (currWrite.struct is Skip) {
              // prefer to slice Skip because the other struct might contain more information
              currWrite.struct.length -= diff;
            } else {
              curr = sliceStruct(curr, diff);
            }
          }
          if (!currWrite.struct.mergeWith(/** @type {any} */ (curr))) {
            writeStructToLazyStructWriter(lazyStructEncoder, currWrite.struct, currWrite.offset);
            currWrite = _Write(curr, 0);
            currDecoder.next();
          }
        }
      }
    } else {
      currWrite = _Write(currDecoder.curr as AbstractStruct, 0);
      currDecoder.next();
    }
    
    for (
      var next = currDecoder.curr;
      next != null && next.id.client == firstClient 
        && next.id.clock == currWrite!.struct.id.clock + currWrite.struct.length 
        && next is! Skip;
      next = currDecoder.next()
    ) {
      writeStructToLazyStructWriter(lazyStructEncoder, currWrite.struct, currWrite.offset);
      currWrite = _Write(next, 0);
    }
  }
  
  if (currWrite != null) {
    writeStructToLazyStructWriter(lazyStructEncoder, currWrite.struct, currWrite.offset);
    currWrite = null;
  }
  finishLazyStructWriting(lazyStructEncoder);

  final dss = updateDecoders.map((decoder) => readDeleteSet(decoder)).toList();
  final ds = mergeDeleteSets(dss);
  writeDeleteSet(updateEncoder, ds);
  return updateEncoder.toUint8Array();
}

/**
 * @param {Uint8Array} update
 * @param {Uint8Array} sv
 * @param {typeof UpdateDecoderV1 | typeof UpdateDecoderV2} [YDecoder]
 * @param {typeof UpdateEncoderV1 | typeof UpdateEncoderV2} [YEncoder]
 */
Uint8List diffUpdateV2(Uint8List update, Uint8List sv, [
    AbstractUpdateDecoder YDecoder(decoding.Decoder decoder)?,
    AbstractUpdateEncoder YEncoder()?,]) {
  YDecoder ??= UpdateDecoderV2.new;
  YEncoder ??= UpdateEncoderV2.new;

  final state = decodeStateVector(sv);
  final encoder = YEncoder();
  final lazyStructWriter = LazyStructWriter(encoder);
  final decoder = YDecoder(decoding.createDecoder(update));
  final reader = LazyStructReader(decoder, false);
  while (reader.curr != null) {
    final curr = reader.curr!;
    final currClient = curr.id.client;
    final svClock = state.get(currClient) ?? 0;
    if (reader.curr is Skip) {
      // the first written struct shouldn't be a skip
      reader.next();
      continue;
    }
    if (curr.id.clock + curr.length > svClock) {
      writeStructToLazyStructWriter(lazyStructWriter, curr, math.max(svClock - curr.id.clock, 0));
      reader.next();
      while (reader.curr != null && reader.curr!.id.client == currClient) {
        writeStructToLazyStructWriter(lazyStructWriter, reader.curr!, 0);
        reader.next();
      }
    } else {
      // read until something new comes up
      while (reader.curr != null && reader.curr!.id.client == currClient && reader.curr!.id.clock + reader.curr!.length <= svClock) {
        reader.next();
      }
    }
  }
  finishLazyStructWriting(lazyStructWriter);
  // write ds
  final ds = readDeleteSet(decoder);
  writeDeleteSet(encoder, ds);
  return encoder.toUint8Array();
}

/**
 * @param {Uint8Array} update
 * @param {Uint8Array} sv
 */
Uint8List diffUpdate(Uint8List update, Uint8List sv) 
  => diffUpdateV2(update, sv, UpdateDecoderV1.new, UpdateEncoderV1.new);

/**
 * @param {LazyStructWriter} lazyWriter
 */
void flushLazyStructWriter(LazyStructWriter lazyWriter) {
  if (lazyWriter.written > 0) {
    lazyWriter.clientStructs.add(PartStructs(lazyWriter.written, encoding.toUint8Array(lazyWriter.encoder.restEncoder)));
    lazyWriter.encoder.restEncoder = encoding.createEncoder();
    lazyWriter.written = 0;
  }
}

/**
 * @param {LazyStructWriter} lazyWriter
 * @param {Item | GC} struct
 * @param {number} offset
 */
void writeStructToLazyStructWriter(LazyStructWriter lazyWriter, AbstractStruct struct, int offset) {
  // flush curr if we start another client
  if (lazyWriter.written > 0 && lazyWriter.currClient != struct.id.client) {
    flushLazyStructWriter(lazyWriter);
  }
  if (lazyWriter.written == 0) {
    lazyWriter.currClient = struct.id.client;
    // write next client
    lazyWriter.encoder.writeClient(struct.id.client);
    // write startClock
    encoding.writeVarUint(lazyWriter.encoder.restEncoder, struct.id.clock + offset);
  }
  struct.write(lazyWriter.encoder, offset);
  lazyWriter.written++;
}
/**
 * Call this function when we collected all parts and want to
 * put all the parts together. After calling this method,
 * you can continue using the UpdateEncoder.
 *
 * @param {LazyStructWriter} lazyWriter
 */
void finishLazyStructWriting(LazyStructWriter lazyWriter) {
  flushLazyStructWriter(lazyWriter);

  // this is a fresh encoder because we called flushCurr
  final restEncoder = lazyWriter.encoder.restEncoder;

  /**
   * Now we put all the fragments together.
   * This works similarly to `writeClientsStructs`
   */

  // write # states that were updated - i.e. the clients
  encoding.writeVarUint(restEncoder, lazyWriter.clientStructs.length);

  for (var i = 0; i < lazyWriter.clientStructs.length; i++) {
    final partStructs = lazyWriter.clientStructs[i];
    /**
     * Works similarly to `writeStructs`
     */
    // write # encoded structs
    encoding.writeVarUint(restEncoder, partStructs.written);
    // write the rest of the fragment
    encoding.writeUint8Array(restEncoder, partStructs.restEncoder);
  }
}

/**
 * @param {Uint8Array} update
 * @param {function(Item|GC|Skip):Item|GC|Skip} blockTransformer
 * @param {typeof UpdateDecoderV2 | typeof UpdateDecoderV1} YDecoder
 * @param {typeof UpdateEncoderV2 | typeof UpdateEncoderV1 } YEncoder
 */
Uint8List convertUpdateFormat (Uint8List update, AbstractStruct blockTransformer(AbstractStruct block), 
    AbstractUpdateDecoder YDecoder(decoding.Decoder decoder), 
    AbstractUpdateEncoder YEncoder()) {
  final updateDecoder = YDecoder(decoding.createDecoder(update));
  final lazyDecoder = LazyStructReader(updateDecoder, false);
  final updateEncoder = YEncoder();
  final lazyWriter = LazyStructWriter(updateEncoder);
  for (var curr = lazyDecoder.curr; curr != null; curr = lazyDecoder.next()) {
    writeStructToLazyStructWriter(lazyWriter, blockTransformer(curr), 0);
  }
  finishLazyStructWriting(lazyWriter);
  final ds = readDeleteSet(updateDecoder);
  writeDeleteSet(updateEncoder, ds);
  return updateEncoder.toUint8Array();
}

/**
 * @typedef {Object} ObfuscatorOptions
 * @property {boolean} [ObfuscatorOptions.formatting=true]
 * @property {boolean} [ObfuscatorOptions.subdocs=true]
 * @property {boolean} [ObfuscatorOptions.yxml=true] Whether to obfuscate nodeName / hookName
 */

class ObfuscatorOptions {
  ObfuscatorOptions({ this.formatting = true, this.subdocs = true, this.yxml = true });

  final bool formatting;
  final bool subdocs;
  final bool yxml;
}

typedef AbstractStruct _ObfuscatorFunction(AbstractStruct block);

/**
 * @param {ObfuscatorOptions} obfuscator
 */
_ObfuscatorFunction createObfuscator(ObfuscatorOptions? options) {
  final _options = options ?? ObfuscatorOptions();

  var i = 0;
  final mapKeyCache = {};
  // final nodeNameCache = {};
  final formattingKeyCache = {};
  final formattingValueCache = {};
  formattingValueCache.set(null, null); // end of a formatting range should always be the end of a formatting range
  /**
   * @param {Item|GC|Skip} block
   * @return {Item|GC|Skip}
   */
  return (AbstractStruct block) {
    if (block is GC || block is Skip) {
      return block;
    } 
    
    if (block is Item) {
      final item = /** @type {Item} */ (block);
      final content = item.content;

      switch (content) {
        case ContentDeleted _: break;
        case ContentType _:
          if (_options.yxml) {
            //TODO:
            /**
            final type = /** @type {ContentType} */ (content).type;
            if (type is YXmlElement) {
              type.nodeName = map.setIfUndefined(nodeNameCache, type.nodeName, () => 'node-' + i)
            }
            if (type is YXmlHook) {
              type.hookName = map.setIfUndefined(nodeNameCache, type.hookName, () => 'hook-' + i)
            }
            */
          }
        case ContentAny c: 
          c.arr = c.arr.map((_) => i).toList();
        case ContentBinary c: 
          c.content = Uint8List.fromList([i]);
        case ContentDoc c: 
          if (_options.subdocs) {
            c.opts = Opts();
            c.doc!.guid = '$i';
          }
        case ContentEmbed c: 
          c.embed = {};

        case ContentFormat c: 
          if (_options.formatting) {
            c.key = formattingKeyCache.putIfAbsent(c.key, () => '$i');
            c.value = formattingValueCache.putIfAbsent(c.value, () => {'i': i});
          }
        case ContentJSON c: 
          c.arr = c.arr.map((_) => i).toList();
        case ContentString c: 
          c.str = '${'${(i % 10)}' * c.str.length}';

        default:
          throw Exception('Unexpected case');
      }

      if (item.parentSub != null) {
        item.parentSub = mapKeyCache.putIfAbsent(item.parentSub, () => '$i');
      }
      i++;
      return block;
    }

    throw Exception('Unexpected case');
  };
}

/**
 * This function obfuscates the content of a Yjs update. This is useful to share
 * buggy Yjs documents while significantly limiting the possibility that a
 * developer can on the user. Note that it might still be possible to deduce
 * some information by analyzing the "structure" of the document or by analyzing
 * the typing behavior using the CRDT-related metadata that is still kept fully
 * intact.
 *
 * @param {Uint8Array} update
 * @param {ObfuscatorOptions} [opts]
 */
Uint8List obfuscateUpdate(Uint8List update, [ObfuscatorOptions? opts]) => convertUpdateFormat(update, createObfuscator(opts), UpdateDecoderV1.new, UpdateEncoderV1.new);

/**
 * @param {Uint8Array} update
 * @param {ObfuscatorOptions} [opts]
 */
Uint8List obfuscateUpdateV2(Uint8List update, [ObfuscatorOptions? opts]) => convertUpdateFormat(update, createObfuscator(opts), UpdateDecoderV2.new, UpdateEncoderV2.new);

/**
 * @param {Uint8Array} update
 */
Uint8List convertUpdateFormatV1ToV2(Uint8List update) => convertUpdateFormat(update, f.id, UpdateDecoderV1.new, UpdateEncoderV2.new);

/**
 * @param {Uint8Array} update
 */
Uint8List convertUpdateFormatV2ToV1(Uint8List update) => convertUpdateFormat(update, f.id, UpdateDecoderV2.new, UpdateEncoderV1.new);
