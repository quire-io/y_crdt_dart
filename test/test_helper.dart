import 'dart:typed_data';
import 'dart:math';

import "package:test/test.dart";

import "package:y_crdt/src/lib0/encoding.dart" as encoding;
import "package:y_crdt/src/lib0/decoding.dart" as decoding;
import "package:y_crdt/src/lib0/prng.dart" as prng;
import "package:y_crdt/src/lib0/testing.dart" show TestCase;
import 'package:y_crdt/src/external/protocol_sync.dart' as syncProtocol;
import 'package:y_crdt/y_crdt.dart' as y;

/**
 * @param {TestYInstance} y // publish message created by `y` to all other online clients
 * @param {Uint8Array} m
 */
void broadcastMessage(TestYInstance y, Uint8List m) {
  if (y.tc.onlineConns.contains(y)) {
    y.tc.onlineConns.forEach((remoteYInstance) {
      if (remoteYInstance != y) {
        remoteYInstance._receive(m, y);
      }
    });
  }
}

var useV2 = false;

/**
 * @typedef {Object} Enc
 * @property {function(Array<Uint8Array>):Uint8Array} Enc.mergeUpdates
 * @property {function(Y.Doc):Uint8Array} Enc.encodeStateAsUpdate
 * @property {function(Y.Doc, Uint8Array):void} Enc.applyUpdate
 * @property {function(Uint8Array):void} Enc.logUpdate
 * @property {function(Uint8Array):{from:Map<number,number>,to:Map<number,number>}} Enc.parseUpdateMeta
 * @property {function(Y.Doc):Uint8Array} Enc.encodeStateVector
 * @property {function(Uint8Array):Uint8Array} Enc.encodeStateVectorFromUpdate
 * @property {'update'|'updateV2'} Enc.updateEventName
 * @property {string} Enc.description
 * @property {function(Uint8Array, Uint8Array):Uint8Array} Enc.diffUpdate
 */
abstract class Enc {

  final String updateEventName, description;

  Enc(this.updateEventName, [this.description = '']);

  Uint8List encodeStateVector(y.Doc doc);

  Uint8List encodeStateAsUpdate(y.Doc doc, [Uint8List? encodedTargetStateVector]);

  Uint8List encodeStateVectorFromUpdate(Uint8List update);

  Uint8List mergeUpdates(Iterable<Uint8List> updates);

  void applyUpdate(y.Doc ydoc, Uint8List update, [dynamic transactionOrigin]);

  void logUpdate(Uint8List update);

  Uint8List diffUpdate(Uint8List update, Uint8List sv);

  (Map<int, int>, Map<int, int>) parseUpdateMeta(Uint8List update);

}

class EncV1 extends Enc {
  EncV1() : super('update', 'V1');

  @override
  Uint8List encodeStateVector(y.Doc doc) {
    return y.encodeStateVector(doc);
  }

  @override
  Uint8List encodeStateAsUpdate(y.Doc doc, [Uint8List? encodedTargetStateVector]) {
    return y.encodeStateAsUpdate(doc, encodedTargetStateVector);
  }

  @override
  Uint8List encodeStateVectorFromUpdate(Uint8List update) {
    return y.encodeStateVectorFromUpdate(update);
  }

  @override
  Uint8List mergeUpdates(Iterable<Uint8List> updates) {
    return y.mergeUpdates(updates);
  }

  @override
  void applyUpdate(y.Doc ydoc, Uint8List update, [dynamic transactionOrigin]) {
    y.applyUpdate(ydoc, update, transactionOrigin);
  }

  @override
  void logUpdate(Uint8List update) {
    y.logUpdate(update);
  }

  @override
  Uint8List diffUpdate(Uint8List update, Uint8List sv) {
    return y.diffUpdate(update, sv);
  }

  @override
  (Map<int, int>, Map<int, int>) parseUpdateMeta(Uint8List update) {
    return y.parseUpdateMeta(update);
  }
}

class EncV2 extends Enc {
  EncV2() : super('updateV2', 'V2');

  @override
  Uint8List encodeStateVector(y.Doc doc) {
    return y.encodeStateVector(doc);
  }

  @override
  Uint8List encodeStateAsUpdate(y.Doc doc, [Uint8List? encodedTargetStateVector]) {
    return y.encodeStateAsUpdateV2(doc, encodedTargetStateVector);
  }

  @override
  Uint8List encodeStateVectorFromUpdate(Uint8List update) {
    return y.encodeStateVectorFromUpdateV2(update);
  }

  @override
  Uint8List mergeUpdates(Iterable<Uint8List> updates) {
    return y.mergeUpdatesV2(updates);
  }

  @override
  void applyUpdate(y.Doc ydoc, Uint8List update, [dynamic transactionOrigin]) {
    y.applyUpdateV2(ydoc, update, transactionOrigin);
  }

  @override
  void logUpdate(Uint8List update) {
    y.logUpdateV2(update);
  }

  @override
  Uint8List diffUpdate(Uint8List update, Uint8List sv) {
    return y.diffUpdateV2(update, sv);
  }

  @override
  (Map<int, int>, Map<int, int>) parseUpdateMeta(Uint8List update) {
    return y.parseUpdateMetaV2(update);
  }
}

var enc = EncV1();

void useV1Encoding() {
  useV2 = false;
  enc = EncV1();
}

void useV2Encoding() {
  print('sync protocol doesnt support v2 protocol yet, fallback to v1 encoding'); // @Todo
  useV2 = false;
  enc = EncV1();
}

class TestYInstance extends y.Doc {

  TestYInstance(this.tc, this.userID) {
    tc.allConns.add(this);

    // set up observe on local model
    this.on(enc.updateEventName, /** @param {Uint8Array} update @param {any} origin */ (args) {
      final update = args[0];
      final origin = args[1];
      if (origin != tc) {
        final encoder = encoding.createEncoder();
        syncProtocol.writeUpdate(encoder, update);
        broadcastMessage(this, encoding.toUint8Array(encoder));
      }
      this.updates.add(update);
    });
    this.connect();
  }

  /**
   * @type {TestConnector}
   */
  final TestConnector tc;

  final int userID; // overwriting clientID

  /**
   * @type {Map<TestYInstance, Array<Uint8Array>>}
   */
  Map<TestYInstance, List<Uint8List>> receiving = <TestYInstance, List<Uint8List>>{};

  /**
   * The list of received updates.
   * We are going to merge them later using Y.mergeUpdates and check if the resulting document is correct.
   * @type {Array<Uint8Array>}
   */
  final updates = <Uint8List>[];

  /**
   * Disconnect from TestConnector.
   */
  void disconnect() {
    this.receiving = {};
    this.tc.onlineConns.remove(this);
  }

  /**
   * Append yourself to the list of known Y instances in testconnector.
   * Also initiate sync with all clients.
   */
  void connect() {
    if (!this.tc.onlineConns.contains(this)) {
      this.tc.onlineConns.add(this);
      final encoder = encoding.createEncoder();
      syncProtocol.writeSyncStep1(encoder, this);
      // publish SyncStep1
      broadcastMessage(this, encoding.toUint8Array(encoder));
      this.tc.onlineConns.forEach((remoteYInstance) {
        if (remoteYInstance != this) {
          // remote instance sends instance to this instance
          final encoder = encoding.createEncoder();
          syncProtocol.writeSyncStep1(encoder, remoteYInstance);
          this._receive(encoding.toUint8Array(encoder), remoteYInstance);
        }
      });
    }
  }

  /**
   * Receive a message from another client. This message is only appended to the list of receiving messages.
   * TestConnector decides when this client actually reads this message.
   *
   * @param {Uint8Array} message
   * @param {TestYInstance} remoteClient
   */
  void _receive(Uint8List message, TestYInstance remoteClient) {
    receiving.putIfAbsent(remoteClient, () => <Uint8List>[]).add(message);
  }
}

/**
 * Keeps track of TestYInstances.
 *
 * The TestYInstances add/remove themselves from the list of connections maiained in this object.
 * I think it makes sense. Deal with it.
 */
class TestConnector {
  /**
   * @param {prng.PRNG} gen
   */
  TestConnector(this._prng);

  final Random _prng;

  /**
   * @type {Set<TestYInstance>}
   */
  final allConns = <TestYInstance>{};
  /**
   * @type {Set<TestYInstance>}
   */
  final onlineConns = <TestYInstance>{};
  /**
   * @type {prng.PRNG}
   */
  // this.prng = gen

  /**
   * Create a new Y instance and add it to the list of connections
   * @param {number} clientID
   */
  TestYInstance createY (clientID) {
    return TestYInstance(this, clientID);
  }

  /**
   * Choose random connection and flush a random message from a random sender.
   *
   * If this function was unable to flush a message, because there are no more messages to flush, it returns false. true otherwise.
   * @return {boolean}
   */
  bool flushRandomMessage () {
    final gen = this._prng;
    final conns = this.onlineConns.where((conn) => conn.receiving.isNotEmpty).toList();
    if (conns.isNotEmpty) {
      final receiver = prng.oneOf(gen, conns);
      final en = prng.oneOf(gen, receiver.receiving.entries.toList()),
        sender = en.key,
        messages = en.value;
      final m = messages.isEmpty ? null: messages.removeAt(0);
      if (messages.isEmpty) {
        receiver.receiving.remove(sender);
      }
      if (m == null) {
        return this.flushRandomMessage();
      }
      final encoder = encoding.createEncoder();
      // console.log('receive (' + sender.userID + '->' + receiver.userID + '):\n', syncProtocol.stringifySyncMessage(decoding.createDecoder(m), receiver))
      // do not publish data created when this function is executed (could be ss2 or update message)
      syncProtocol.readSyncMessage(decoding.createDecoder(m), encoder, receiver, receiver.tc);
      if (encoding.length(encoder) > 0) {
        // send reply message
        sender._receive(encoding.toUint8Array(encoder), receiver);
      }
      return true;
    }
    return false;
  }

  /**
   * @return {boolean} True iff this function actually flushed something
   */
  bool flushAllMessages () {
    var didSomething = false;
    while (this.flushRandomMessage()) {
      didSomething = true;
    }
    return didSomething;
  }

  void reconnectAll () {
    this.allConns.forEach((conn) => conn.connect());
  }

  void disconnectAll () {
    this.allConns.forEach((conn) => conn.disconnect());
  }

  void syncAll () {
    this.reconnectAll();
    this.flushAllMessages();
  }

  /**
   * @return {boolean} Whether it was possible to disconnect a randon connection.
   */
  bool disconnectRandom () {
    if (this.onlineConns.isEmpty) {
      return false;
    }
    prng.oneOf(this._prng, this.onlineConns.toList()).disconnect();
    return true;
  }

  /**
   * @return {boolean} Whether it was possible to reconnect a random connection.
   */
  bool reconnectRandom () {
    /**
     * @type {Array<TestYInstance>}
     */
    final reconnectable = <TestYInstance>[];
    this.allConns.forEach((conn) {
      if (!this.onlineConns.contains(conn)) {
        reconnectable.add(conn);
      }
    });
    if (reconnectable.isEmpty) {
      return false;
    }
    prng.oneOf(this._prng, reconnectable).connect();
    return true;
  }
}


/**
 * @template T
 * @param {t.TestCase} tc
 * @param {{users?:number}} conf
 * @param {InitTestObjectCallback<T>} [initTestObject]
 * @return {{testObjects:Array<any>,testConnector:TestConnector,users:Array<TestYInstance>,array0:Y.Array<any>,array1:Y.Array<any>,array2:Y.Array<any>,map0:Y.Map<any>,map1:Y.Map<any>,map2:Y.Map<any>,map3:Y.Map<any>,text0:Y.Text,text1:Y.Text,text2:Y.Text,xml0:Y.XmlElement,xml1:Y.XmlElement,xml2:Y.XmlElement}}
 */
// void init(tc, { users = 5 } = {}, initTestObject) {
Map<String, dynamic> init(TestCase tc, {int users = 5, initTestObject(TestYInstance user)?}) {
  /**
   * @type {Object<string,any>}
   */
  final userList = [],
    result = <String, dynamic>{
      'users': userList
    };
  final gen = tc.prng;
  // choose an encoding approach at random
  if (prng.randomBool(gen)) {
    useV2Encoding();
  } else {
    useV1Encoding();
  }

  final testConnector = TestConnector(gen);
  result['testConnector'] = testConnector;
  for (var i = 0; i < users; i++) {
    final yInc = testConnector.createY(i);
    yInc.clientID = i;
    userList.add(yInc);
    result['array$i'] = yInc.getArray('array');
    result['map$i'] = yInc.getMap('map');
    result['xml$i'] = yInc.get('xml', y.YXmlElement.new);
    result['text$i'] = yInc.getText('text');
  }
  testConnector.syncAll();
  // result.testObjects = result.users.map(initTestObject || (() => null))
  useV1Encoding();
  return /** @type {any} */ result;
}


/**
 * 1. reconnect and flush all
 * 2. user 0 gc
 * 3. get type content
 * 4. disconnect & reconnect all (so gc is propagated)
 * 5. compare os, ds, ss
 *
 * @param {Array<TestYInstance>} users
 */
void compare(List users) {
  users.cast<TestYInstance>().forEach((u) => u.connect());
  final user0 = users[0] as TestYInstance;
  while (user0.tc.flushAllMessages()) {}
  // For each document, merge all received document updates with Y.mergeUpdates and create a new document which will be added to the list of "users"
  // This ensures that mergeUpdates works correctly
  final mergedDocs = users.cast<TestYInstance>().map((user) {
    final ydoc = y.Doc();
    enc.applyUpdate(ydoc, enc.mergeUpdates(user.updates));
    return ydoc;
  }).toList();
  users.addAll(mergedDocs);
  final userArrayValues = users.cast<y.Doc>().map((u) => u.getArray('array').toJSON()).toList();
  final userMapValues = users.cast<y.Doc>().map((u) => u.getMap('map').toJSON()).toList();
  final userXmlValues = users.cast<y.Doc>().map((u) => u.get('xml', y.YXmlElement.new).toString()).toList();
  final userTextValues = users.cast<y.Doc>().map((u) => u.getText('text').toDelta()).toList();
  for (final u in users.cast<y.Doc>()) {
    expect(u.store.pendingDs, null);
    expect(u.store.pendingStructs, null);
  }
  // Test Array iterator
  expect(user0.getArray('array').toArray(), equals(user0.getArray('array').toList()));
  // Test Map iterator
  final ymapkeys = user0.getMap('map').keys().toList();
  expect(ymapkeys.length, userMapValues[0].keys.length);
  ymapkeys.forEach((key) => expect(userMapValues[0].containsKey(key), isTrue));
  /**
   * @type {Object<string,any>}
   */
  final mapRes = {};
  user0.getMap('map').forEach((v, k, _) {
    mapRes[k] = v is y.AbstractType ? v.toJSON() : v;
  });
  expect(userMapValues[0], equals(mapRes));
  // Compare all users
  for (var i = 0; i < users.length - 1; i++) {
    expect(userArrayValues[i].length, (users[i] as y.Doc).getArray('array').length);
    expect(userArrayValues[i], equals(userArrayValues[i + 1]));
    expect(userMapValues[i], equals(userMapValues[i + 1]));
    expect(userXmlValues[i], equals(userXmlValues[i + 1]));
    expect(userTextValues[i].map(/** @param {any} a */ (a) 
      => a['insert'] is String ? a['insert'] : ' ').join('').length, 
      (users[i] as y.Doc).getText('text').length);

    // (_constructor, a, b) => {
    //   if (a is y.AbstractType) {
    //     expect(a.toJSON(), b.toJSON())
    //   } else if (a !== b) {
    //     t.fail('Deltas dont match')
    //   }
    //   return true
    // }

    mapItem(item) {
      return item is y.AbstractType ? item.toJSON() : item;
    }
    expect(userTextValues[i].map(mapItem), equals(userTextValues[i + 1].map(mapItem)));
    expect(y.encodeStateVector(users[i]), equals(y.encodeStateVector(users[i + 1])));
    y.equalDeleteSets(y.createDeleteSetFromStructStore(users[i].store), 
      y.createDeleteSetFromStructStore(users[i + 1].store));
    compareStructStores(users[i].store, users[i + 1].store);
    expect(y.encodeSnapshot(y.snapshot(users[i])), 
      y.encodeSnapshot(y.snapshot(users[i + 1])));
  }
  users.map((u) => u.destroy());
}


/**
 * @param {Y.Item?} a
 * @param {Y.Item?} b
 * @return {boolean}
 */
bool compareItemIDs(y.Item? a, y.Item? b) {
  return a == b || (a != null && b != null && y.compareIDs(a.id, b.id));
}


/**
 * @param {import('../src/internals.js').StructStore} ss1
 * @param {import('../src/internals.js').StructStore} ss2
 */
void compareStructStores(y.StructStore ss1, y.StructStore ss2) {
  expect(ss1.clients.length, ss2.clients.length);
  for (final en in ss1.clients.entries) {
    final client = en.key,
      structs1 = en.value,
      structs2 = /** @type {Array<Y.AbstractStruct>} */ (ss2.clients.get(client));
    expect(structs2 != null && structs1.length == structs2.length, true);
    for (var i = 0; i < structs1.length; i++) {
      final s1 = structs1[i];
      final s2 = structs2![i];
      // checks for abstract struct
      if (
        s1.runtimeType != s2.runtimeType ||
        !y.compareIDs(s1.id, s2.id) ||
        s1.deleted != s2.deleted ||
        // @ts-ignore
        s1.length != s2.length
      ) {
        expect(false, true, reason: 'Structs dont match');
      }
      if (s1 is y.Item) {
        if (
          s2 is! y.Item ||
          !((s1.left == null && s2.left == null) || (s1.left != null && s2.left != null 
            && y.compareIDs(s1.left!.lastId, s2.left!.lastId))) ||
          !compareItemIDs(s1.right, s2.right) ||
          !y.compareIDs(s1.origin, s2.origin) ||
          !y.compareIDs(s1.rightOrigin, s2.rightOrigin) ||
          s1.parentSub != s2.parentSub
        ) {
          // return t.fail('Items dont match')
          expect(false, true, reason: 'Items dont match');
        }
        // make sure that items are connected correctly
        expect(s1.left == null || s1.left!.right == s1, true);
        expect(s1.right == null || s1.right!.left == s1, true);
        expect((s2 as y.Item).left == null || s2.left!.right == s2, true);
        expect(s2.right == null || s2.right!.left == s2, true);
      }
    }
  }
}