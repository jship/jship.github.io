---
title: "Writing Performant Haskell (5 of 6): Dive Into Text"
author: Jason Shipman
tags: Haskell, Performance, Hexy Tutorial
---

<div class="ui icon info message">
  <i class="info icon"></i>
  <div class="content"><div class="header">Edited: August 15, 2017</div><p>Thanks to <a href="https://www.reddit.com/user/bos">/u/bos</a> and <a href="https://www.reddit.com/user/mrkkrp">/u/mrkkrp</a> over on <a href="https://www.reddit.com/r/haskell/comments/6trxhs/writing_performant_haskell_5_of_6_dive_into_text/">Reddit</a> for helping to improve the quality of this post!  The previous version was unnecessarily using GHC primops.</p></div>
</div>

### Recap

In the [previous post](/posts/2017-08-12-writing-performant-haskell-part-4.html), we improved our usage of `Builder` by introducing a new data type that kept track of a `Builder` value and its length.  We also learned a bit about strictness.  Our API looked like this:

```haskell
class HexShow a where
  xbuild :: a -> Builder
  xbuildu :: a -> Builder

xshow :: HexShow a => a -> Text.Text
xshowp :: HexShow a => a -> Text.Text
xshowu :: HexShow a => a -> Text.Text
xshowpu :: HexShow a => a -> Text.Text
xshowl :: HexShow a => a -> Text.Lazy.Text
xshowlp :: HexShow a => a -> Text.Lazy.Text
xshowlu :: HexShow a => a -> Text.Lazy.Text
xshowlpu :: HexShow a => a -> Text.Lazy.Text
```

After we improved our usage of `Builder`, the [benchmark report](/html/writing-performant-haskell-part-4-bench-4.html)'s summary looked like this:

<img class="ui fluid image" src="/images/writing-performant-haskell-part-4-bench-4-summary.png">

We chopped off anywhere from roughly 100 to 200 nanoseconds for each of the functions in `Hexy`'s public API.

In this post, we finally return to the proposition from the [second post](/posts/2017-08-10-writing-performant-haskell-part-2.html) that using `text` gives us more optimization flexibility.  We will dive into the internals of the `text` package and hopefully come out with some seriously fast functions.

### `text` and Arrays

The `text` package is using packed arrays under the hood.  As a reminder, a strict `Text` is a packed array, while a lazy `Text` is a list of packed arrays.  If arrays drive `text`'s performance, it sure would be nice if we could make like a C programmer and `malloc` precisely the amount of storage we need for our hex strings:

```c
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

const char* xbuild(uint32_t v)
{
  char* s = malloc(2 * sizeof(v) + 1);
  // implementation details...
  return s;
}
```

This would allow us to work on fixed-size buffers and the contents of each buffer would be contiguous in memory.  An approach like this directly opposes the API we have built so far.  Our API leverages `Builder` and dynamically builds up the hex strings.  The user then chooses whether they want a `Builder` value, a strict `Text` value, or a lazy `Text` value.  For all instances of our `HexShow` typeclass, we know exactly how much storage we need for the result strings:  Twice the size in bytes of the input type, and maybe a couple characters for the `0x` prefix.  We are not taking full advantage of this knowledge.

Let's dig down into the internals of `text` - I promise we will maintain most of our sanity!

### Evolving the API

If we want to get away from `Builder` and move to manually allocating storage for strict `Text` values, we need to alter our API.  We will scrap returning `Builder` altogether:

```haskell
class HexShow a where
  xshow :: a -> Text.Text
  xshowp :: a -> Text.Text
  xshowu :: a -> Text.Text
  xshowpu :: a -> Text.Text
  xshowl :: a -> Text.Lazy.Text
  xshowlp :: a -> Text.Lazy.Text
  xshowlu :: a -> Text.Lazy.Text
  xshowlpu :: a -> Text.Lazy.Text

  {-# MINIMAL xshowp, xshowpu #-}
```

We have also bundled all our functions under the `HexShow` typeclass.  To implement instances, we only need to implement `xshowp` and `xshowpu` then we will get the rest of the functions for free.  Remember that `xshowp` converts its input to a lowercase hex string, zero-padded based on the size of the input type, and prefixed with `0x`.  `xshowpu` is identical to `xshowp` except its returned hex string is uppercase.

In a way, we have turned our API upside-down.  Previously, we were building the zero-padded hex string and then, if needed, tacking on the `0x` prefix.  Now we are requiring that instances implement the functions to build the full zero-padded, `0x`-prefixed hex string and then instances will get the remaining variants for free.

This is in line with our goal of allocating just the amount of space we need for the hex string.  Going ahead and allocating for the 2 additonal `0x` prefix characters regardless of whether or not our users want to use the prefix variants will save us from a possible reallocation for the prefix later.

Sometimes we have to make breaking API changes in the name of performance!

### Internal Implementation

Let's get to hacking on `Hexy.Internal`.  The extremely interesting top portion of the module:

```haskell
{-# LANGUAGE BangPatterns #-}

module Hexy.Internal where

import Control.Monad.ST (ST)
import qualified Data.Char as Char
import Data.Int (Int, Int8, Int16, Int32, Int64)
import qualified Data.Text as Text
import qualified Data.Text.Array as Text.Array
import qualified Data.Text.Internal as Text.Internal
import qualified Data.Text.Internal.Private as Text.Internal.Private
import qualified Data.Text.Internal.Unsafe.Char as Text.Internal.Unsafe.Char
import Data.Word (Word, Word8, Word16, Word32, Word64)
import Foreign.Storable (Storable(..))
import qualified Foreign.Storable as Storable
```

Below we have a couple new functions that will be core to implementing our `HexShow` typeclass instances:

```haskell
showHexTextLower :: (Integral a, Show a, Storable a) => a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
showHexTextLower = textShowIntAtBase 16 intToDigitLower

showHexTextUpper :: (Integral a, Show a, Storable a) => a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
showHexTextUpper = textShowIntAtBase 16 intToDigitUpper
```

Note that unlike `xbuild` and `xbuildu`, these are returning strict `Text` values.

Let's go ahead and define those lowercase and uppercase functions:

```haskell
intToDigitLower :: Int -> Char
intToDigitLower i
  | i >=  0 && i <=  9 = Text.Internal.Unsafe.Char.unsafeChr (fromIntegral $ Char.ord '0' + i)
  | i >= 10 && i <= 15 = Text.Internal.Unsafe.Char.unsafeChr (fromIntegral $ Char.ord 'a' + i - 10)
  | otherwise = errorWithoutStackTrace ("Hexy.Internal.intToDigitLower: not a digit " ++ show i)

intToDigitUpper :: Int -> Char
intToDigitUpper i
  | i >=  0 && i <=  9 = Text.Internal.Unsafe.Char.unsafeChr (fromIntegral $ Char.ord '0' + i)
  | i >= 10 && i <= 15 = Text.Internal.Unsafe.Char.unsafeChr (fromIntegral $ Char.ord 'A' + i - 10)
  | otherwise = errorWithoutStackTrace ("Hexy.Internal.intToDigitUpper: not a digit " ++ show i)
```

`intToDigitLower` is a slightly modified copy of the `intToDigit` function from `base`'s `Data.Char` module.  These functions are comparing the input value against the inclusive 0-9 range and the inclusive 10-15 range.  Depending upon which range the input value is in, the function returns the ASCII-adjusted hex `Char` representation of the `Int` value.

The `unsafeChr` function from `text` converts its input `Word16` to a `Char` value - there is no bounds checking.  Think of `unsafeChr` like a cast from C:

```c
int i = 42;
char c = (char) i;
```

Now we will implement our most important function:

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      buffer <- Text.Array.new size
      let hexLoop i (n, d) = do
            i' <- unsafeWriteRev buffer i c
            case n of
              0 -> pure i'
              _ -> hexLoop i' (quotRem n base)
           where
            c = toChr $ fromIntegral d
      let zeroPadLoop i
            | i < 2 = pure i
            | otherwise = do
                i' <- unsafeWriteRev buffer i '0'
                zeroPadLoop i'
      j <- hexLoop (size - 1) (quotRem n0 base)
      k <- zeroPadLoop j
      l <- unsafeWriteRev buffer k 'x'
      _ <- unsafeWriteRev buffer l '0'
      done buffer size
```

`textShowIntAtBase` looks a good bit different from the previous incarnation's `buildWordAtBase` and is a lot to take in.  We will break this down.

Our 2 initial guards are identical to the `buildWordAtBase` version:

```haskell
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
```

The `otherwise` guard is where things get interesting:

```haskell
  | otherwise = Text.Internal.Private.runText $ \done -> do
      -- ...
```

The [`runText`](https://hackage.haskell.org/package/text-1.2.2.1/docs/src/Data-Text-Internal-Private.html#runText) function is coming from the internals of the `text` package.  Haskell libaries (including `Hexy`!) often provide a clear divide between what is the public API and what is internal to the library.  "Internal to the library" means the functions are used in the library but are not necessarily expected to be used by clients of the library.  Any internal modules are subject to change and may not respect invariants so if we decide to use them, we must do so at our own risk!

Package modules are conventionally marked as internal modules via placing them under a subdirectory called `Internal` or being housed entirely in a `Internal.hs` module.  Authors generally still export these internal modules for client use so users can, for example, eke out more performance or use the package in ways the authors never anticipated.  If you are authoring a package, note that choosing to not export internal modules is generally frowned upon in the community as it can limit what users can do with your package.

Fortunately for us, the internal modules in `text` are exported and clearly marked with an `Internal` somewhere in the module name, i.e.

```haskell
Data.Text.Internal
Data.Text.Internal.Fusion
Data.Text.Lazy.Internal
-- and so on...
```

Have a look at the [docs](https://hackage.haskell.org/package/text) to see the various internal modules.

What does `runText` do though?  Let's start with its type:

```haskell
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

That type is notably scary and gives rise to a few questions.  What is an `MArray`?  What is `ST`?  Why is there a `forall s`?

At a high level, `runText` is taking in 1 gnarly parameter and returning a strict `Text` value.  We should break this down further:

```haskell
                             The output value, a strict `Text` -------+
                                                                      |
                                                                      v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

```haskell
           +------- The single gnarly input value, this is a
           |        function we define
           v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

```haskell
The function we define must produce a strict Text ------+
in the ST monad                                         |
                                                        v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

```haskell
                      +------- Utility function that is passed to the function
                      |        we define. We call this at the end of the
                      |        function we define to get our Text in ST,
                      |        hence why we named it 'done' above.
                      v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

```haskell
                       +------- The mutable array we must build in the
                       |        function we define
                       v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

```haskell
The length of the mutable array ---+
                                   |
                                   v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

```haskell
The utility function returns the ---------+
result Text in ST                         |
                                          v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

```haskell
                   +------- Phantom type for the ST monad that prevents
                   |        the internal state from being accessible
                   |        outside of the computation
                   v
runText :: (forall s. (MArray s -> Int -> ST s Text) -> ST s Text) -> Text
```

---

We will not go into details in this blog post series on how the `ST` monad works, so try not to get hung up on the `s` type parameter.  For our purposes, it suffices to think of `ST` as a `State` monad that allows for in-place mutation.  Unlike when we are in `IO`, the mutation we do in `ST` is not externally visible to other parts of our program, so extracting results from `ST` is pure.

The mutation we are doing is on `MArray s` values.  These are mutable arrays [provided](https://hackage.haskell.org/package/text-1.2.2.1/docs/Data-Text-Array.html) by the `text` package.

<div class="ui icon negative message">
  <i class="warning icon"></i>
  <p>Look out world!  We are about to put on our imperative Haskell hats.</p>
</div>

Let's view a bit more of our `textShowIntAtBase`.  The first thing we do is determine the array size we will need.  The only difference in our size calculation now versus the one from previous posts is that we now add `2` to account for the `0x` prefix:

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      -- implementation details...
```

Now we allocate an array with the computed size and bind it to `buffer`.  The type of `new` is `Int -> ST s (MArray s)`.  We give it an `Int` value representing the size of the array we want and it spits out an uninitialized array of that size.

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      buffer <- Text.Array.new size
      -- implementation details...
```

We then define a `hexLoop` function with type `Int -> (a, a) -> ST s Int`.  `hexLoop` is the spiritual successor to [`buildIt`](https://github.com/jship/hexy/blob/e3530765891768a98a4718c9c80ec2727f909145/library/Hexy/Internal.hs#L92) from the previous post.  It takes in a write index and the current `quotRem` result, and in-place writes to `buffer` as it `quotRem`'s down `n0`.  It uses a function we have not defined yet - `unsafeWriteRev` - to write each character.  `unsafeWriteRev` returns the write index given to it minus 1, hence the `...Rev` suffix.  We are writing to the array from back to front.  When `hexLoop` is done, it returns the next index to begin writing to for zero-padding.

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      buffer <- Text.Array.new size
      let hexLoop i (n, d) = do
            i' <- unsafeWriteRev buffer i c
            case n of
              0 -> pure i'
              _ -> hexLoop i' (quotRem n base)
           where
            c = toChr $ fromIntegral d
      -- implementation details...
```

Next, we define a `zeroPadLoop` function with type `Int -> ST s Int`.  `zeroPadLoop` recursively fills the rest of the array with `'0'` characters, going from where `hexLoop` will leave off.  `zeroPadLoop` stops before writing to index 0 and 1, as that is where the `0x` prefix will be written.  When `zeroPadLoop` is done, it returns the next index to begin writing to for the `0x` prefix.

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      buffer <- Text.Array.new size
      let hexLoop i (n, d) = do
            i' <- unsafeWriteRev buffer i c
            case n of
              0 -> pure i'
              _ -> hexLoop i' (quotRem n base)
           where
            c = toChr $ fromIntegral d
      let zeroPadLoop i
            | i < 2 = pure i
            | otherwise = do
                i' <- unsafeWriteRev buffer i '0'
                zeroPadLoop i'
      -- implementation details...
```

Let's call our `hexLoop` and `zeroPadLoop` functions, making sure to respect the write indices they return:

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      buffer <- Text.Array.new size
      let hexLoop i (n, d) = do
            i' <- unsafeWriteRev buffer i c
            case n of
              0 -> pure i'
              _ -> hexLoop i' (quotRem n base)
           where
            c = toChr $ fromIntegral d
      let zeroPadLoop i
            | i < 2 = pure i
            | otherwise = do
                i' <- unsafeWriteRev buffer i '0'
                zeroPadLoop i'
      j <- hexLoop (size - 1) (quotRem n0 base)
      k <- zeroPadLoop j
      -- implementation details...
```

Now we will write the `0x` prefix, respecting write indices from `unsafeWriteRev`:

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      buffer <- Text.Array.new size
      let hexLoop i (n, d) = do
            i' <- unsafeWriteRev buffer i c
            case n of
              0 -> pure i'
              _ -> hexLoop i' (quotRem n base)
           where
            c = toChr $ fromIntegral d
      let zeroPadLoop i
            | i < 2 = pure i
            | otherwise = do
                i' <- unsafeWriteRev buffer i '0'
                zeroPadLoop i'
      j <- hexLoop (size - 1) (quotRem n0 base)
      k <- zeroPadLoop j
      l <- unsafeWriteRev buffer k 'x'
      _ <- unsafeWriteRev buffer l '0'
      -- implementation details...
```

The final bit we need to complete our function is to call the `done` utility passed into our function.  This [utility function](https://hackage.haskell.org/package/text-1.2.2.1/docs/src/Data-Text-Internal-Private.html#runText) will "freeze" up the mutable array we give it, i.e. converting it into an immutable array.  It then creates a `Text` for us in `ST` using the immutable array and the size:

```haskell
textShowIntAtBase :: (Integral a, Show a, Storable a) => a -> (Int -> Char) -> a -> Text.Text
-- a bunch of SPECIALIZE pragmas...
textShowIntAtBase base toChr n0
  | base <= 1 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to unsupported base " ++ show base)
  | n0   <  0 = errorWithoutStackTrace ("Hexy.Internal.textShowIntAtBase: applied to negative number " ++ show n0)
  | otherwise = Text.Internal.Private.runText $ \done -> do
      let !size = 2 + (2 * Storable.sizeOf n0)
      buffer <- Text.Array.new size
      let hexLoop i (n, d) = do
            i' <- unsafeWriteRev buffer i c
            case n of
              0 -> pure i'
              _ -> hexLoop i' (quotRem n base)
           where
            c = toChr $ fromIntegral d
      let zeroPadLoop i
            | i < 2 = pure i
            | otherwise = do
                i' <- unsafeWriteRev buffer i '0'
                zeroPadLoop i'
      j <- hexLoop (size - 1) (quotRem n0 base)
      k <- zeroPadLoop j
      l <- unsafeWriteRev buffer k 'x'
      _ <- unsafeWriteRev buffer l '0'
      done buffer size  -- done :: MArray s -> Int -> ST s Text
```

Below is the definition for `unsafeWriteRev`.  It uses `unsafeWrite` from `text` and then returns the preceding write index:

```haskell
unsafeWriteRev :: Text.Array.MArray s -> Int -> Char -> ST s Int
unsafeWriteRev buffer i c = do
  Text.Array.unsafeWrite buffer i (fromIntegral (Text.Internal.Unsafe.Char.ord c))
  pure (i - 1)
```

The last piece of functionality we need to complete our `Hexy.Internal` module is a means to drop the hex prefix, for use by functions like `xshow` and `xshowu`.  Here we will use the internal constructor for strict `Text` values, which takes an immutable array, an offset into the array, and the length of the array:

```haskell
unsafeDropHexPrefix :: Text.Text -> Text.Text
unsafeDropHexPrefix (Text.Internal.Text arr _ len) = Text.Internal.Text arr 2 (len - 2)
```

Note that we could have used `Data.Text`'s [`drop`](https://hackage.haskell.org/package/text-1.2.2.1/docs/src/Data-Text.html#drop) function from `text`'s public API, but the above definition should be a bit faster.  Try benchmarking the two different functions to see if there is any difference.

### Public API

We will need to update our public API in the `Hexy` module to use our new internal functions:

```haskell
module Hexy
  ( HexShow(..)
  ) where

import Hexy.Internal (showHexTextLower, showHexTextUpper, unsafeDropHexPrefix)

import Data.Int (Int, Int16, Int32, Int64, Int8)
import qualified Data.Text as Text
import qualified Data.Text.Lazy as Text.Lazy
import Data.Word (Word, Word8, Word16, Word32, Word64)

class HexShow a where
  xshow :: a -> Text.Text
  xshow = unsafeDropHexPrefix . xshowp

  xshowp :: a -> Text.Text

  xshowu :: a -> Text.Text
  xshowu = unsafeDropHexPrefix . xshowpu

  xshowpu :: a -> Text.Text

  xshowl :: a -> Text.Lazy.Text
  xshowl = Text.Lazy.fromStrict . xshow

  xshowlp :: a -> Text.Lazy.Text
  xshowlp = Text.Lazy.fromStrict . xshowp

  xshowlu :: a -> Text.Lazy.Text
  xshowlu = Text.Lazy.fromStrict . xshowu

  xshowlpu :: a -> Text.Lazy.Text
  xshowlpu = Text.Lazy.fromStrict . xshowpu

  {-# MINIMAL xshowp, xshowpu #-}

instance HexShow Word32 where
  xshowp  = showHexTextLower
  xshowpu = showHexTextUpper

-- remaining instances
```

### Test Check

Our public API has changed so our unit tests need some work.  Have a look at the full test suite on [GitHub](https://github.com/jship/hexy/blob/23321173371a5bfa77459f366ede8e9b2c05a5a3/test-suite/Test/HexyTest.hs) if you like.

### Performance Check

In the previous post, our [benchmark results](/html/writing-performant-haskell-part-4-bench-4.html) looked like this:

<img class="ui fluid image" src="/images/writing-performant-haskell-part-4-bench-4-summary.png">

Let's run the benchmarks again:

```bash
$ stack bench --benchmark-arguments "--output bench.html"
```

View the full report from this run [here](/html/writing-performant-haskell-part-5-bench.html).  The summary looks like this:

<img class="ui fluid image" src="/images/writing-performant-haskell-part-5-bench-summary.png">

This is our greatest performance improvement yet - all of our functions clock in at approximately 50 nanoseconds!  They are roughly 5 times faster than their previous iterations.  Our users can call either the strict or the lazy variants with no penalty.  Furthermore, our functions are about 2.65 times faster than `base`'s `showHex` and are doing more work via zero-padding and prefixing with `0x`

<img class="ui centered image" src="/images/mission_accomplished_baby.jpg">

### Maintenance

While our performance gains were fantastic, we should take note that the performance comes at a maintenance cost.  We have chosen to use the internals of `text` and `text` makes no guarantees the functions we have used will be available in future versions.  Fortunately, the portions we are using of `text`'s internal API have seemingly been stable for quite some time (years), so we feel relatively comfortable with our changes.

### Safety

Multiple functions were used above that were prefixed with `unsafe...`.  These functions do not do any bounds checking so we have to be very careful when working with them to avoid access violations.  Testing is always important, but it is even more so when we are going imperative like we did above.

Another callout is that `text`'s arrays are _packed_ UTF-16.  We took advantage of the fact that the hex characters we write have small enough integral values that we can always get away with 1 write instead of 2.  If we [poke around](https://hackage.haskell.org/package/text-1.2.2.1/docs/src/Data-Text-Internal-Unsafe-Char.html#unsafeWrite) in the bowels of `text`, we can see a few places where the code decides whether to write 1 or 2 `Word16` values for a given write of 1 `Char` value.  We are not doing this at all in our code.

### What's next?

In the next and final post, we will update our benchmark suite to cover all the data types `Hexy` supports and take stock of our performance gains overall.

All code in this post is available on [GitHub](https://github.com/jship/hexy/tree/23321173371a5bfa77459f366ede8e9b2c05a5a3).
