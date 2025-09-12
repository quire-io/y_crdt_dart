import "package:test/test.dart";

import 'dart:async';
import 'dart:math';

import "package:dart_quill_delta/dart_quill_delta.dart" show Operation;

void printRed(String msg) {
  // ignore: avoid_print
  print('\x1B[31m$msg\x1B[0m');
}

void printGreen(String msg) {
  // ignore: avoid_print
  print('\x1B[32m$msg\x1B[0m');
}

void printYellow(String msg) {
  // ignore: avoid_print
  print('\x1B[33m$msg\x1B[0m');
}

void printBlue(String msg) {
  // ignore: avoid_print
  print('\x1B[34m$msg\x1B[0m');
}

List<Map> deltaToArray(List<Operation> delta) {
  return delta.map((item) => item.toJson()).toList();
}

class TestCase {
  final String moduleName, name;
  TestCase(this.moduleName, this.name);

  /**
   * This type can store custom information related to the TestCase
   *
   * @type {Map<string,any>}
   */
  final meta = <String, dynamic>{};

  // final prng = Random(DateTime.now().millisecondsSinceEpoch);

  int? _seed;
  Random? _prng;


  resetSeed () {
    this._seed = null;
    this._prng = null;
  }

  /**
   * @type {number}
   */
  /* c8 ignore next */
  int get seed {
    /* c8 ignore else */
    if (this._seed == null) {
      /* c8 ignore next */
      this._seed = Random().nextInt(1 << 32);
    }
    return this._seed!;
  }

  /**
   * A PRNG for this test case. Use only this PRNG for randomness to make the test case reproducible.
   *
   * @type {prng.PRNG}
   */
  Random get prng {
    /* c8 ignore else */
    if (this._prng == null) {
      this._prng = Random(this.seed);
    }
    return this._prng!;
  }
}

// export const repetitionTime = Number(env.getParam('--repetition-time', '50'))
const repetitionTime = 50; // ms

final repeatTestRegex = RegExp(r'^(repeat|repeating)\s');

/**
 * @param {string} moduleName
 * @param {string} name
 * @param {function(TestCase):void|Promise<any>} f
 * @param {number} i
 * @param {number} numberOfTests
 */
Future<bool> run(String moduleName, String name, Future f(TestCase tc), i, numberOfTests) async {
  // final uncamelized = string.fromCamelCase(name.slice(4), ' ');
  // final filtered = !testFilterRegExp.test(`[${i + 1}/${numberOfTests}] ${moduleName}: ${uncamelized}`);
  /* c8 ignore next 3 */
  // if (filtered) {
  //   return true;
  // }
  final tc = TestCase(moduleName, name);
  final repeat = name.isEmpty;
  // final repeat = repeatTestRegex.hasMatch(uncamelized);
  // final groupArgs = [log.GREY, `[${i + 1}/${numberOfTests}] `, log.PURPLE, `${moduleName}: `, log.BLUE, uncamelized]
  /* c8 ignore next 5 */
  // if (testFilter === null) {
  //   log.groupCollapsed(...groupArgs)
  // } else {
  //   log.group(...groupArgs)
  // }
  final times = <int>[];
  // final start = performance.now()
  final start = DateTime.now().millisecondsSinceEpoch;
  var lastTime = start;
  /**
   * @type {any}
   */
  var err;
  // performance.mark(`${name}-start`)
  do {
    try {
      await f(tc);
    } catch (_err) {
      err = _err;
    }
    // final currTime = performance.now()
    final currTime = DateTime.now().millisecondsSinceEpoch;
    times.add(currTime - lastTime);
    lastTime = currTime;
    if (repeat && err == null && (lastTime - start) < repetitionTime) {
      tc.resetSeed();
    } else {
      break;
    }
  } while (err == null && (lastTime - start) < repetitionTime);
  // performance.mark(`${name}-end`)
  /* c8 ignore next 3 */
  // if (err !== null && err.constructor !== SkipError) {
  //   log.printError(err)
  // }
  // performance.measure(name, `${name}-start`, `${name}-end`)
  // log.groupEnd()
  // final duration = lastTime - start;
  var success = true;
  // times.sort((a, b) => a - b);
  /* c8 ignore next 3 */
  // final againMessage = env.isBrowser
  //   ? `     - ${window.location.host + window.location.pathname}?filter=\\[${i + 1}/${tc._seed === null ? '' : `&seed=${tc._seed}`}`
  //   : `\nrepeat: npm run test -- --filter "\\[${i + 1}/" ${tc._seed === null ? '' : `--seed ${tc._seed}`}`
  // final timeInfo = (repeat && err === null)
  //   ? ` - ${times.length} repetitions in ${time.humanizeDuration(duration)} (best: ${time.humanizeDuration(times[0])}, worst: ${time.humanizeDuration(array.last(times))}, median: ${time.humanizeDuration(statistics.median(times))}, average: ${time.humanizeDuration(statistics.average(times))})`
  //   : ` in ${time.humanizeDuration(duration)}`
  if (err != null) {
    /* c8 ignore start */
    // if (err.constructor === SkipError) {
    //   log.print(log.GREY, log.BOLD, 'Skipped: ', log.UNBOLD, uncamelized)
    // } else {
      success = false;
      printRed('Failure: $moduleName: $name');
      // log.print(log.RED, log.BOLD, 'Failure: ', log.UNBOLD, log.UNCOLOR, uncamelized, log.GREY, timeInfo, againMessage)
    // }
    /* c8 ignore stop */
  } else {
    // log.print(log.GREEN, log.BOLD, 'Success: ', log.UNBOLD, log.UNCOLOR, uncamelized, log.GREY, timeInfo, againMessage)
    printGreen( 'Success: $moduleName: $name' );
  }
  return success;
}

typedef Future TestFunc(TestCase tc);


/**
 * @param {Object<string, Object<string, function(TestCase):void|Promise<any>>>} tests
 */
Future<bool> runTests(Map<String, Map<String, TestFunc>> tests) async {
  /**
   * @param {string} testname
   */
  // bool filterTest(String testname) => testname.startsWith('test') || testname.startsWith('benchmark');

  // const numberOfTests = object.map(tests, mod => object.map(mod, (f, fname) => /* c8 ignore next */ f && filterTest(fname) ? 1 : 0).reduce(math.add, 0)).reduce(math.add, 0)
  final numberOfTests = tests.length;
  var successfulTests = 0;
  var testnumber = 0;
  // final start = performance.now();
  for (final en in tests.entries) {
    final modName = en.key;

    group(modName, () async {
      for (final en in en.value.entries) {
        final fname = en.key,
          f = en.value;
        /* c8 ignore else */
        // if (filterTest(fname)) {
          final repeatEachTest = 1;
          var success = true;
          test(fname, () async {
            for (var i = 0; success && i < repeatEachTest; i++) {
              success = await run(modName, fname, f, testnumber, numberOfTests);
            }
          });
          testnumber++;
          /* c8 ignore else */
          if (success) {
            successfulTests++;
          }
        // }
      }
    });
  }
  // final end = performance.now()
  // log.print('')
  final success = successfulTests == numberOfTests;
  /* c8 ignore start */
  if (success) {
    print('All tests successful!');
    // log.print(log.GREEN, log.BOLD, 'All tests successful!', log.GREY, log.UNBOLD, ` in ${time.humanizeDuration(end - start)}`)
    // log.printImgBase64(nyanCatImage, 50)
  } else {
    final failedTests = numberOfTests - successfulTests;
    // log.print(log.RED, log.BOLD, `> ${failedTests} test${failedTests > 1 ? 's' : ''} failed`)
    print('> ${failedTests} test${failedTests > 1 ? 's' : ''} failed');
  }
  /* c8 ignore stop */
  return success;
}