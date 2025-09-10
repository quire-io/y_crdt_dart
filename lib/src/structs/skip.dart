// import {
//   AbstractStruct,
//   UpdateEncoderV1, UpdateEncoderV2, StructStore, Transaction, ID // eslint-disable-line
// } from '../internals.js'

import 'package:y_crdt/src/lib0/encoding.dart' as encoding;
// import * as error from 'lib0/error'
// import * as encoding from 'lib0/encoding'

import 'package:y_crdt/src/structs/abstract_struct.dart';
import 'package:y_crdt/src/utils/struct_store.dart';
import 'package:y_crdt/src/utils/transaction.dart';
import 'package:y_crdt/src/utils/update_encoder.dart';


const structSkipRefNumber = 10;

/**
 * @private
 */
class Skip extends AbstractStruct {

  Skip(super.id, super.length);

  @override
  bool get deleted {
    return true;
  }

  void delete() {}

  /**
   * @param {Skip} right
   * @return {boolean}
   */
  @override
  bool mergeWith(AbstractStruct right) {
    if (right is! Skip) {
      return false;
    }
    this.length += right.length;
    return true;
  }

  /**
   * @param {Transaction} transaction
   * @param {number} offset
   */
  @override
  void integrate(Transaction transaction, int offset) {
    // skip structs cannot be integrated
    throw Exception('Unexpected case');
  }

  /**
   * @param {UpdateEncoderV1 | UpdateEncoderV2} encoder
   * @param {number} offset
   */
  @override
  void write(AbstractUpdateEncoder encoder, int offset) {
    encoder.writeInfo(structSkipRefNumber);
    // write as VarUint because Skips can't make use of predictable length-encoding
    encoding.writeVarUint(encoder.restEncoder, this.length - offset);
  }

  /**
   * @param {Transaction} transaction
   * @param {StructStore} store
   * @return {null | number}
   */
  int? getMissing(Transaction transaction, StructStore store) {
    return null;
  }
}
