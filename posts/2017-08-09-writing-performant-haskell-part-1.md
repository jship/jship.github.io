---
title: "Writing Performant Haskell (1 of 6): Intro"
author: Jason Shipman
tags: Haskell, Performance, Hexy Tutorial
---

### Performance Haskell

As Haskell developers, we are fortunate that [GHC](https://www.haskell.org/ghc/) is capable of producing extremely fast binaries for us.  Often, we can get away with writing programs that are "fast enough" without any manual optimization on our part - i.e. set engines to `-O` or `-O2` and blast off!  This is a good thing as it allows us to focus on problem solving close to the domain and not the nitty-gritty operational details of our code.

GHC is not a silver bullet though.  If we want to take our code beyond the subjective realm of "fast enough", we will have to lend the compiler a hand.

This post series will serve as a guide for a few of the approaches we can take to optimize Haskell programs.  We will build a small but complete Haskell package, iteratively improving on its performance.  As a result, these posts may be useful for new Haskellers too as multiple areas of package development will be touched on - `hpack`, testing, benchmarking, etc.

As a disclaimer, I am not an expert at performance Haskell.  If you see any inaccuracies or ways to achieve even more speed, please let me know.  Note that speed concerns you spot early on might already be addressed later in the post series.  We will start out with slow code after all, or else we would not have anything to optimize!

<div class="ui icon info message">
  <i class="info icon"></i>
  <p>The rest of this post creates a project, fleshes out the initial version of the API, adds tests, and adds benchmarks. Haskellers only interested in the optimization approaches may wish to skip ahead to subsequent posts.</p>
</div>

### Initializing Hexy

In this post series, we will build a package to pretty-print numbers in hexadecimal.  Let's initialize our project via `stack`, using the `haskeleton` template:

```bash
$ stack new hexy haskeleton && cd hexy
```

If `stack` informs you that it is missing pieces of metadata - items like author name, email, and so on, visit [this link](http://docs.haskellstack.org/en/stable/yaml_configuration/) to setup a `config.yaml` for `stack` and avoid manually filling in the fields after initializing every project.

The `haskeleton` template gives us a nice starting point to build our package:

```bash
$ ls -1
benchmark/
CHANGELOG.md
executable/
hexy.cabal
library/
LICENSE.md
package.yaml
README.md
Setup.hs
stack.yaml
test-suite/
```

We have separate directories for our library, test suite, and benchmarking code, as well as a handful of top-level files.  Among these files is a  `package.yaml`.  Our package uses [`hpack`](https://hackage.haskell.org/package/hpack) to generate the project's `hexy.cabal` file.  `stack` has seamless support for `hpack`, so we never have to call the `hpack` binary ourselves.  Building via `stack` is sufficient:

```bash
$ stack build
```

`hpack`'s `package.yaml` file format is pure YAML.  It is inclusive by default, meaning for example, we tell it our library's source directory and it treats all Haskell modules in that directory as part of our public API.  This is in contrast to the `<project_name>.cabal` file where we must explicitly specify each Haskell module.  I encourage you to form your own opinion of Cabal's `<project_name>.cabal` file versus `hpack`'s `package.yaml` file.  For new Haskellers, please do not feel like you must use `hpack`.  Use whichever you prefer!

### Hexy's API

Let's get rid of `haskeleton`'s default library file `Example.hs` and make our own:

```bash
$ rm library/Example.hs
$ rm -r executable/
$ echo "module Hexy () where" > library/Hexy.hs
$ mkdir library/Hexy
$ echo "module Hexy.Internal () where" > library/Hexy/Internal.hs
```

Be sure to remove the whole `executables` section from the `package.yaml` file too or else you will get a build error.

Now we will flesh out the types of our API's initial dev version in `library/Hexy.hs`:

```haskell
module Hexy
  ( HexShow(..)
  , xshowp
  , xshowpu
  ) where

-- | Conversion of values to hexadecimal 'String's.
class HexShow a where
  -- | Builds a zero-padded, lowercase hexadecimal `String` from a value.
  --
  -- @
  -- xshow (0x1f :: Word32) = "0000001f"
  -- @
  xshow :: a -> String

  -- | Builds a zero-padded, uppercase hexadecimal `String` from a value.
  --
  -- @
  -- xshowu (0x1f :: Word32) = "0000001F"
  -- @
  xshowu :: a -> String

-- | Converts a value to a zero-padded, prefixed, lowercase hexadecimal `String`.
--
-- @
-- xshowp (0x1f :: Word32) = "0x0000001f"
-- @
xshowp :: HexShow a => a -> String
xshowp = undefined

-- | Converts a value to a zero-padded, prefixed, uppercase hexadecimal `String`.
--
-- @
-- xshowpu (0x1f :: Word32) = "0x0000001F"
-- @
xshowpu :: HexShow a => a -> String
xshowpu = undefined
```

We have a `HexShow` typeclass that lets us build lowercase hexadecimal strings via `xshow` and uppercase ones via `xshowu`.  The idea of having lowercase and uppercase as separate typeclass functions is that instances can potentially have optimized functions for each case.  The remaining functions have input that is constrained to instances of `HexShow` and will give us the hexadecimal string in various formats.

The above functions follow a convention to save our users precious horizontal screen space.  If the function is suffixed with a `p`, the output `String` will be prefixed with `0x`.  If the function is suffixed with a `u`, the output `String` will use uppercase `A-F` instead of lowercase `a-f`.  If the function is suffixed with both a `p` and a `u`, the output `String` will both be prefixed with `0x` and it will be uppercased.

Our goal will be to implement `xshow` and `xshowu` for various `Integral` data types and then we can write the remaining `undefined` functions in terms of `xshow` and `xshowu`.

### Hexy's Initial Implementation

Let's implement the `HexShow` typeclass for `Word32` to get started.  We will do this in our `Hexy.Internal` module to keep the implementation details hidden from our public API in the `Hexy` module:

```haskell
module Hexy.Internal
  ( xshowWord32
  , xshowuWord32
  ) where

import qualified Data.Char as Char
import Data.Word (Word32)
import qualified Numeric

xshowWord32 :: Word32 -> String
xshowWord32 w = zeroPaddedHex (Numeric.showHex w "")
 where
  zeroPaddedHex hex = go numPadCharsNeeded hex
   where
    go 0 s = s
    go n s = go (n - 1) ('0' : s)
    numPadCharsNeeded = lengthWithoutPrefix - length hex
    -- 4 bytes in a Word32 means we need 8 characters to store the nibbles
    lengthWithoutPrefix = 8

xshowuWord32 :: Word32 -> String
xshowuWord32 = fmap Char.toUpper . xshowWord32
```

As a warning, the above is an intentionally naïve implementation.  We are using the `Numeric` module's [`showHex`](https://hackage.haskell.org/package/base-4.9.1.0/docs/Numeric.html#v:showHex) function from `base` to do all the work for us and then we are zero-padding the result.  `xshowuWord32` is "cheating" too by offloading to `xshowWord32` and uppercasing the result.

For new Haskellers, keep in mind that there is nothing wrong with exploring your library design spaces in the way we have done above.  It is better to have a working implementation that can be optimized later than to have no implementation at all!

Now we will hook up our package's internals to our public API in the `Hexy` module:

```haskell
-- ...
import Hexy.Internal

import Data.Word (Word32)
-- ...
instance HexShow Word32 where
  xshow = xshowWord32
  xshowu = xshowuWord32
```

We will do a quick test in GHCi to give us a warm-and-fuzzy on whether or not our implementation is correct:

```bash
$ stack ghci
Configuring GHCi with the following packages: hexy
GHCi, version 8.0.2: http://www.haskell.org/ghc/  :? for help
[1 of 2] Compiling Hexy.Internal
[2 of 2] Compiling Hexy
Ok, modules loaded: Hexy, Hexy.Internal.
Loaded GHCi configuration
*Hexy.Internal Hexy Hexy.Internal> xshow (0x1f :: Word32)
"0000001f"
*Hexy.Internal Hexy Hexy.Internal> xshowu (0x1f :: Word32)
"0000001F"
```

Looks good to me.  `xshow` gave us the lowercase version and `xshowu` gave us the uppercase version.  Both results are zero-padded based on the size in bytes of `Word32` (i.e. 4 byte value means our string should have 8 characters).

A single instance is not super useful for our users though.  We would like to add instances for all `Word`, `Word8`, `Word16`, `Word32`, `Word64`, `Int`, `Int8`, `Int16`, `Int32`, `Int64` so we will need functions for each one...  Wait, for real?  It would be a pain to write all those and surely we can do better.  Let's put Haskell's typeclasses and polymorphism to work and get back to hacking on `Hexy.Internal`!

```haskell
module Hexy.Internal
  ( xshowStorable
  , xshowuStorable
  , prefixHex
  ) where

import qualified Data.Char as Char
import Foreign.Storable (Storable)
import qualified Foreign.Storable as Storable
import qualified Numeric

xshowStorable :: (Integral a, Show a, Storable a) => a -> String
xshowStorable v = zeroPaddedHex (Numeric.showHex v "")
 where
  zeroPaddedHex hex = go numPadCharsNeeded hex
   where
    go 0 s = s
    go n s = go (n - 1) ('0' : s)
    numPadCharsNeeded = lengthWithoutPrefix - length hex
    lengthWithoutPrefix = fromIntegral $ 2 * Storable.sizeOf v

xshowuStorable :: (Integral a, Show a, Storable a) => a -> String
xshowuStorable = fmap Char.toUpper . xshowStorable

prefixHex :: String -> String
prefixHex hex = '0' : 'x' : hex
```

The `xshowStorable` function's type signature is saying "gimme an integral, storable value and I'll give you the hexadecimal string representation".  We use the `Storable` constraint so we can use the [`sizeOf`](https://hackage.haskell.org/package/base-4.9.1.0/docs/Foreign-Storable.html#v:sizeOf) function instead of hard-coding our character count to 8 for `Word32`.  We also take on the [`Integral`](http://hackage.haskell.org/package/base-4.9.1.0/docs/Prelude.html#t:Integral) constraint because we only want to deal with integral types and not types like [`FunPtr`](https://hackage.haskell.org/package/base-4.9.1.0/docs/Foreign-Ptr.html#t:FunPtr).  The [`Show`](http://hackage.haskell.org/package/base-4.9.1.0/docs/Prelude.html#t:Show) constraint is only there because `showHex` requires it.

We went ahead and added a `prefixHex` function too that slaps a `0x` on the front of the input string.

Now back in `Hexy`:

```haskell
instance HexShow Word32 where
  xshow = xshowStorable
  xshowu = xshowuStorable
```

Test this in GHCi to gain some confidence that it works like the previous concrete `Word32` implementation.

We may be tempted to try to get all our remaining instances in one fell swoop by swapping out the instance for `Word32` with this:

```haskell
instance (Integral a, Show a, Storable a) => HexShow a where
  xshow = xshowStorable
  xshowu = xshowuStorable
```

The above would require the [`UndecidableInstances`](https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#undecidable-instances) extension though so we will roll our sleeves up and add all our instances (a.k.a. spam copy-paste and find/replace until it builds):

```haskell
instance HexShow Int where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Int8 where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Int16 where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Int32 where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Int64 where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Word where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Word8 where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Word16 where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Word32 where
  xshow = xshowStorable
  xshowu = xshowuStorable

instance HexShow Word64 where
  xshow = xshowStorable
  xshowu = xshowuStorable
```

We will test in GHCi to see if our functions work for a few of the different types:

```haskell
$ stack ghci
Configuring GHCi with the following packages: hexy
GHCi, version 8.0.2: http://www.haskell.org/ghc/  :? for help
[1 of 2] Compiling Hexy.Internal
[2 of 2] Compiling Hexy
Ok, modules loaded: Hexy, Hexy.Internal.
Loaded GHCi configuration
*Hexy.Internal Hexy Hexy.Internal> import Data.Int
*Hexy.Internal Hexy Hexy.Internal Data.Int> import Data.Word
*Hexy.Internal Hexy Hexy.Internal Data.Int Data.Word> xshow (0xdeadbeef :: Word64)
"00000000deadbeef"
*Hexy.Internal Hexy Hexy.Internal Data.Int Data.Word> xshow (0xdeadbeef :: Int64)
"00000000deadbeef"
*Hexy.Internal Hexy Hexy.Internal Data.Int Data.Word> xshowu (0xdeadbeef :: Word32)
"DEADBEEF"
*Hexy.Internal Hexy Hexy.Internal Data.Int Data.Word> xshow (0xabcd :: Word16)
"abcd"
*Hexy.Internal Hexy Hexy.Internal Data.Int Data.Word> xshowu (0xff :: Word8)
"FF"
*Hexy.Internal Hexy Hexy.Internal Data.Int Data.Word> xshowu (0x7f :: Int8)
"7F"
```

Now we need to finish implementing our API's functions:

```haskell
xshowp :: HexShow a => a -> String
xshowp = prefixHex . xshow

xshowpu :: HexShow a => a -> String
xshowpu = prefixHex . xshowu
```

These ones are nice because we get to leverage `HexShow`'s functions.  The only additional work we have to do is prepending the `0x`.  Feel free to test these in GHCi to make sure they check out.

And with that, we have completed our initial implementation of the `Hexy` library!

### Testing

It is hard to trust code without tests.  Having a test suite will also make our optimization iterations _significantly_ safer as we can hit our experimental changes up against it.  Remember: working code is always better than faster but broken code!

Let's add some tests.  We will start by changing up our test suite's dependencies in our `package.yaml`.  The `tests` section should look like this when we are done:

```yaml
tests:
  hexy-test-suite:
    dependencies:
    - base
    - hexy
    - quickcheck-instances
    - tasty
    - tasty-auto
    - tasty-quickcheck
    ghc-options:
    - -rtsopts
    - -threaded
    - -with-rtsopts=-N
    main: Main.hs
    source-dirs: test-suite
```

We will be using [`tasty-auto`](https://hackage.haskell.org/package/tasty-auto-0.2.0.0) to get nice auto-discovery of our test functions.  `tasty-auto` is deprecated in favor of [`tasty-discover`](https://hackage.haskell.org/package/tasty-discover-3.0.2), but the version of `tasty-discover` in the Stackage [LTS snapshot](https://www.stackage.org/lts-8.23) we are using is older so we will stick with `tasty-auto` for now.

For our purposes, we will also be using `QuickCheck` generative property-based testing, so we have taken on the `tasty-quickcheck` dependency.  `tasty` is a great testing framework that lets us pretty seamlessly blend property tests, unit tests, spec (BDD) tests, and so on, all in the same test suite.

We will now wire up `tasty-auto` like this in `test-suite/Main.hs`:

```haskell
{-# OPTIONS_GHC -F -pgmF tasty-auto #-}
```

This tells GHC to call the `tasty-auto` binary during preprocessing via the [`-pgmF`](http://ghc.readthedocs.io/en/8.0.2/phases.html#ghc-flag--pgmF) flag.  `tasty-auto` will recurse down our `test-suite` directory and pick up any files suffixed with `Test.hs` or `Test.lhs`.

Now we add a test file:

```bash
$ mkdir test-suite/Test
$ echo "module Test.HexyTest where" > test-suite/Test/HexyTest.hs
```

Running `stack test` at this point should succeed even though we have no test functions defined.  Here is the abridged contents of our `test-suite/Test/HexyTest.hs` file:

```haskell
module Test.HexyTest where

import Hexy

-- More imports...

data Casing = Casing'Lower | Casing'Upper

prop_xshow_Int :: Positive Int -> Bool
prop_xshow_Int (Positive v) = xshowEqShowHexStorable Casing'Lower v

prop_xshow_Word :: Word -> Bool
prop_xshow_Word = xshowEqShowHexStorable Casing'Lower

-- More properties testing xshow for the remaining instances...

prop_xshowu_Int :: Positive Int -> Bool
prop_xshowu_Int (Positive v) = xshowEqShowHexStorable Casing'Upper v

prop_xshowu_Word :: Word -> Bool
prop_xshowu_Word = xshowEqShowHexStorable Casing'Upper

-- More properties testing xshowu for the remaining instances...

prop_xshowp_Int :: Positive Int -> Bool
prop_xshowp_Int (Positive v) = xshowpEqShowHexStorable Casing'Lower v

prop_xshowp_Word :: Word -> Bool
prop_xshowp_Word = xshowpEqShowHexStorable Casing'Lower

-- More properties testing xshowp for the remaining instances...

prop_xshowpu_Int :: Positive Int -> Bool
prop_xshowpu_Int (Positive v) = xshowpEqShowHexStorable Casing'Upper v

prop_xshowpu_Word :: Word -> Bool
prop_xshowpu_Word = xshowpEqShowHexStorable Casing'Upper

-- More properties testing xshowpu for the remaining instances...

xshowEqShowHexStorable :: (HexShow a, Integral a, Show a, Storable a) => Casing -> a -> Bool
xshowEqShowHexStorable c v = showHexy c v == paddedHexViaShowHex c v

xshowpEqShowHexStorable :: (HexShow a, Integral a, Show a, Storable a) => Casing -> a -> Bool
xshowpEqShowHexStorable c v = showHexyWithPrefix c v == "0x" <> paddedHexViaShowHex c v

-- Functions to get results from the Hexy API
-- ...

-- Functions to get results from base Numeric module
-- ...
```

Running `stack test` now will give us:

```bash
test-suite\Main.hs
  xshow Int:      OK
    +++ OK, passed 100 tests.
  xshow Word:     OK
    +++ OK, passed 100 tests.
  ...
  xshowu Int:     OK
    +++ OK, passed 100 tests.
  xshowu Word:    OK
    +++ OK, passed 100 tests.
  ...
  xshowp Int:     OK
    +++ OK, passed 100 tests.
  xshowp Word:    OK
    +++ OK, passed 100 tests.
  ...
  xshowpu Int:    OK
    +++ OK, passed 100 tests.
  xshowpu Word:   OK
    +++ OK, passed 100 tests.
  ...

All 40 tests passed (0.02s)
```

Cool - `QuickCheck` has generated hundreds of test cases for us and they all pass!  Our test code uses the `showHex` function from `base` as a reference implementation, ensuring that in all the generated tests, our Hexy API matches up with `showHex`'s results.  The power-to-weight ratio of `QuickCheck` is amazing.  Props (heh) to `tasty-auto` as well for automatically picking up all of our test functions with a `prop_` prefix.

If you wish to see the full test file, view it on [GitHub](https://github.com/jship/hexy/blob/fab8bce4aad7651875455d96f4c3fcd33a35251a/test-suite/Test/HexyTest.hs).

### Benchmarking

Our implementation checks out - both from interacting with it via GHCi and in our property tests.  Now we need to write a benchmark suite.

We will begin with a group of benchmarks that test various ways to get a hex string for `Word32` only.  Focusing on a single data type to start will help us keep our sanity.  Copy the contents below into `benchmark/Main.hs`:

```haskell
import Criterion.Main

import Hexy

import Data.Word (Word32)
import Numeric (showHex)
import Text.Printf (printf)

main :: IO ()
main = defaultMain
  [ bgroup "Word32"
    [ bench "printf"  $ nf (printf "%08x" :: Word32 -> String) 0x1f
    , bench "showHex" $ nf (showHex (0x1f :: Word32)) ""
    , bench "xshow"   $ nf xshow    (0x1f :: Word32)
    , bench "xshowp"  $ nf xshowp   (0x1f :: Word32)
    , bench "xshowu"  $ nf xshowu   (0x1f :: Word32)
    , bench "xshowpu" $ nf xshowpu  (0x1f :: Word32)
    ]
  ]
```

We are using the excellent [`criterion`](https://hackage.haskell.org/package/criterion-1.1.4.0) package for our benchmarking.  There is an [official tutorial](http://www.serpentine.com/criterion/tutorial.html) that is definitely worth a read.

With `criterion`, we group our benchmarks with the `bgroup` function.  Above, we have named our benchmark group `Word32`.  We then pass in a list of `Benchmarkable`.  Our `Benchmarkable`s consist of two reference implementations - `printf` and `showHex` from `base` - as well as our four `Hexy` API functions.

<div class="ui icon message">
  <i class="sticky note outline icon"></i>
  <p>We are lucky that we get to vet the performance of our library functions against a couple functions from `base`, though we will keep in mind that the `showHex` function does not provide zero-padding.</p>
</div>

The `nf` function has type:

```haskell
nf :: NFData b => (a -> b) -> a -> Benchmarkable
```

This might seem strange as we are passing in our functions to `nf` with all but their last argument filled in. Our "almost-saturated" benchmark functions fit the `(a -> b)` and each benchmark function's last argument fits the `a`.  The result type of our benchmark functions must be an instance of `NFData`, which means it can be deeply evaluated.  More formally, it can be evaluated to [normal form](http://www.serpentine.com/criterion/tutorial.html#benchmarking-an-io-action).  What we are saying in these `bench` calls is "test the time of evaluating this function, including evaluating the result to normal form".  We must pass our pure functions in "almost-saturated" so that the evaluation results are not memoized.  Behind the scenes, `criterion` runs our functions many times to determine an accurate execution time.  If we passed in our functions "saturated", the result would be cached and we would not be benchmarking much of anything!

For info on laziness, weak-head normal form, and normal form, I recommend reading [this bit](http://www.serpentine.com/criterion/tutorial.html#benchmarking-pure-functions) of the Criterion tutorial and [this section](http://chimera.labs.oreilly.com/books/1230000000929/ch02.html#sec_par-eval-whnf) of Simon Marlow's _Parallel and Concurrent Programming in Haskell_.

Note that `criterion` also provides a `whnf` function that is identical to `nf` except it only evaluates the result to weak-head normal form (i.e. first constructor).  It can be tricky knowing when to evaluate to weak-head normal form or going all the way to normal form.  In our case, our API is intended to provide human-readable hex strings printed out to a screen, file, etc.  Our users will need the fully evaluated hex strings, so we used `nf`.

We will run our benchmarks via `stack`:

```bash
$ stack bench --benchmark-arguments "--output bench.html"
```

We have told `criterion` to give us pretty HTML output.  `criterion` will also print the result summary to the screen:

```bash
$ stack bench --benchmark-arguments "--output bench.html"
hexy-0.0.0: benchmarks
Running 1 benchmarks...
Benchmark hexy-benchmarks: RUNNING...
benchmarking Word32/printf
time                 1.605 us   (1.590 us .. 1.624 us)
                     0.999 R²   (0.999 R² .. 0.999 R²)
mean                 1.625 us   (1.611 us .. 1.641 us)
std dev              55.32 ns   (47.10 ns .. 71.64 ns)
variance introduced by outliers: 46% (moderately inflated)

benchmarking Word32/showHex
time                 130.5 ns   (129.2 ns .. 131.8 ns)
                     0.999 R²   (0.999 R² .. 1.000 R²)
mean                 131.8 ns   (130.7 ns .. 133.3 ns)
std dev              4.049 ns   (3.476 ns .. 4.644 ns)
variance introduced by outliers: 47% (moderately inflated)

benchmarking Word32/xshow
time                 196.1 ns   (194.6 ns .. 197.9 ns)
                     0.999 R²   (0.999 R² .. 1.000 R²)
mean                 196.1 ns   (194.3 ns .. 198.5 ns)
std dev              7.402 ns   (5.765 ns .. 9.874 ns)
variance introduced by outliers: 56% (severely inflated)

benchmarking Word32/xshowp
time                 206.6 ns   (205.4 ns .. 208.0 ns)
                     1.000 R²   (0.999 R² .. 1.000 R²)
mean                 208.2 ns   (206.5 ns .. 210.0 ns)
std dev              5.899 ns   (4.414 ns .. 7.315 ns)
variance introduced by outliers: 42% (moderately inflated)

benchmarking Word32/xshowu
time                 571.7 ns   (569.1 ns .. 574.5 ns)
                     1.000 R²   (1.000 R² .. 1.000 R²)
mean                 572.4 ns   (569.6 ns .. 576.0 ns)
std dev              10.78 ns   (9.069 ns .. 13.47 ns)
variance introduced by outliers: 22% (moderately inflated)

benchmarking Word32/xshowpu
time                 580.4 ns   (577.2 ns .. 584.1 ns)
                     1.000 R²   (0.999 R² .. 1.000 R²)
mean                 584.2 ns   (580.7 ns .. 589.1 ns)
std dev              13.71 ns   (11.59 ns .. 16.43 ns)
variance introduced by outliers: 31% (moderately inflated)

Benchmark hexy-benchmarks: FINISH
```

The text output is nice for quick benchmark-checking, and the HTML report gives us a great visual representation.  You can view the benchmark report from this run [here](/html/writing-performant-haskell-part-1-bench.html).

The bottom of the report gives us info on how to interpret the report's graphs.  For our purposes, we will stick to the summary view at the top.  This gives us a consolidated bar graph of the timings of our functions:

<img class="ui fluid image" src="/images/writing-performant-haskell-part-1-bench-summary.png">

We see the following results:

* `printf`: 1.62 microseconds (micro, not nano!!!)
* `showHex`: 132 nanoseconds
* `xshow`: 196 nanoseconds
* `xshowp`: 208 nanoseconds
* `xshowu`: 572 nanoseconds
* `xshowpu`: 584 nanoseconds

It is important to think about whether or not the numbers from a benchmarking run actually make sense. `showHex` was the fastest.  It makes sense that our API functions are slower than `showHex` - even though they are implemented with `showHex` - because they also zero-pad.  Looking at `xshow` and `xshowp` in isolation, it makes sense that `xshow` is faster because it skips prefixing with `0x`.  Same with `xshowu` and `xshowpu`.  Comparing `xshow` to `xshowu` or `xshowp` to `xshowpu`, the lowercase versions are significantly faster.  Reminder: I mentioned we were "cheating" in the uppercase implementations because we just uppercased the results from the lowercase versions.  Lastly, `printf` from `base` is incredibly slow relative to the other functions, but we will cut `printf` some slack.  `printf` can handle all kinds of crazy formats but `showHex` and our `Hexy` functions can only pretty-print hex.

Based on this benchmarking run, we should be able to considerably speed up our functions.

### What's next?

In the [next post](/posts/2017-08-10-writing-performant-haskell-part-2.html), we will take stock of the core result type used in our API - `String` - and see if we can make a better choice.

All code in this post is available on [GitHub](https://github.com/jship/hexy/tree/fab8bce4aad7651875455d96f4c3fcd33a35251a).
