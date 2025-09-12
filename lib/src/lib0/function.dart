/**
 * Calls all functions in `fs` with args. Only throws after all functions were called.
 *
 * @param {Array<function>} fs
 * @param {Array<any>} args
 */
void callAll(List<Function> fs, List<dynamic> args, [int i = 0]) {
  try {
    for (; i < fs.length; i++) {
      if (args.isEmpty) {
        fs[i].call();
      } else {
        fs[i].call(args.toList());
      }
    }
  } finally {
    if (i < fs.length) {
      callAll(fs, args, i + 1);
    }
  }
}

/**
 * Common functions and function call helpers.
 *
 * @module function
 */

T id<T>(T v) => v;