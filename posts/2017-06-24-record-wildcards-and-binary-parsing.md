---
title: "RecordWildCards and Binary Parsing"
author: Jason Shipman
tags: Cereal, Haskell, Language Extension, Parsing, Quick Tip
---

### `RecordWildCards`

`RecordWildCards` is a GHC extension that makes working with Haskell records more convenient.  The extension has been [blogged](https://ocharles.org.uk/blog/posts/2014-12-04-record-wildcards.html) about in a few [places](https://kseo.github.io/posts/2014-02-10-record-wildcards.html) already, so this post intends to provide a different motivating example: binary parsing.

Kwang's linked blogpost shows binary serialization using the extension.  This post will show the improvements we get with `RecordWildCards` and binary deserialization, but first...

### What does `RecordWildCards` do?

`RecordWildCards` provides local bindings for the fields in a record:

```haskell
#!/usr/bin/env stack
-- stack --resolver lts-8.20 --install-ghc exec ghci --package text

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

import Data.Monoid ((<>))
import Data.Text (Text, intercalate)
import Data.Text.IO (putStrLn)
import Prelude hiding (putStrLn)

data BlogPost = BlogPost
  { blogPostTitle  :: Text
  , blogPostTags   :: [Text]
  }

samplePost :: BlogPost
samplePost = BlogPost "Foo" ["Bar", "Baz, Quux"]

-- Pattern matching is convenient but fiddly when new fields are
-- added or existing fields are rearranged.
printViaPatternMatching :: BlogPost -> IO ()
printViaPatternMatching (BlogPost title tags) = do
  putStrLn $ "Title: " <> title
  putStrLn $ "Tags: " <> intercalate ", " tags

-- Record accessors are not fiddly when new fields are added or existing fields
-- are rearranged, but require more keystrokes and horizontal space.
printViaRecordAccessors :: BlogPost -> IO ()
printViaRecordAccessors blogPost = do
  putStrLn $ "Title: " <> blogPostTitle blogPost
  putStrLn $ "Tags: " <> intercalate ", " (blogPostTags blogPost)

-- RecordWildCards offers the best of both worlds with the above two
-- approaches. We use the field names directly as bindings to the
-- record's values.
printViaRecordWildCards :: BlogPost -> IO ()
printViaRecordWildCards BlogPost{..} = do
  putStrLn $ "Title: " <> blogPostTitle
  putStrLn $ "Tags: " <> intercalate ", " blogPostTags
```

You can execute the above script with `stack` and it will spin up `GHCi`.

### How does it help with binary parsing?

Let's use [cereal](https://www.stackage.org/lts-8.20/package/cereal-0.5.4.0) as our binary parsing library.  Here are the imports we'll need:

```haskell
#!/usr/bin/env stack
-- stack --resolver lts-8.20 --install-ghc exec ghci --package bytestring --package cereal

{-# LANGUAGE RecordWildCards #-}

import Data.ByteString (ByteString)
import Data.Serialize.Get (Get, getWord8, getWord16le, runGet)
import Data.Word (Word8, Word16)
```

We will keep the domain fun and pretend we have a simple video game configuration we need to parse out of a file.  Why we are using a binary file format for this is above our paygrade apparently:

```haskell
data GameConfig = GameConfig
  { gameConfigScreenWidth  :: Word16
  , gameConfigScreenHeight :: Word16
  , gameConfigVolume       :: Word8
  } deriving (Show)

decodeGameConfig :: Get GameConfig -> ByteString -> Either String GameConfig
decodeGameConfig = runGet
```

Now we need to provide a `Get GameConfig` and we'll be off to the races.  There are multiple ways we can tackle this, and the [docs](https://hackage.haskell.org/package/cereal-0.5.4.0/docs/Data-Serialize-Get.html#t:Get) indicate `Get` has instances for `Applicative` and `Monad`.

I typically reach for `Applicative` by default when I need to parse something simple:

```haskell
applicativeGetter :: Get GameConfig
applicativeGetter = GameConfig <$> getWord16le <*> getWord16le <*> getWord8
```

This has a drawback though: the pieces being parsed are not named.  If we look at the parser in isolation, all we know is that a `GameConfig` wraps two `Word16`s and one `Word8` and the fields are laid out in that order in the data declaration.

Another option would be to monadically parse the `GameConfig`:

```haskell
monadicGetter :: Get GameConfig
monadicGetter = do
  screenWidth <- getWord16le
  screenHeight <- getWord16le
  volume <- getWord8
  pure $ GameConfig screenWidth screenHeight volume
```

This provides instant understanding of the meaning of the fields we are parsing.  We know what a `GameConfig` represents without flipping over to its declaration.  The disadvantage over the `Applicative` approach is that we must ensure we are passing the field values in the correct order to the `GameConfig` constructor.  What if we got sleepy and wrote the last line like this?

```haskell
  pure $ GameConfig screenHeight screenWidth volume
```

A third approach would be to still parse monadically but use record syntax at the end:

```haskell
monadicGetterWithRecordSyntax :: Get GameConfig
monadicGetterWithRecordSyntax = do
  screenWidth <- getWord16le
  screenHeight <- getWord16le
  volume <- getWord8
  pure $ GameConfig
    { gameConfigScreenWidth = screenWidth
    , gameConfigScreenHeight = screenHeight
    , gameConfigVolume = volume
    }
```

This somewhat helps alleviate the problem of the sleepy dev, but now the parser is almost twice as many lines and we could still incorrectly write the last bit like this:

```haskell
  pure $ GameConfig
    { gameConfigScreenWidth = screenHeight
    , gameConfigScreenHeight = screenWidth
    , gameConfigVolume = volume
    }
```

Let's see what we can do now that we have `RecordWildCards` in our toolbelt:

```haskell
monadicGetterWithRecordWildCards :: Get GameConfig
monadicGetterWithRecordWildCards = do
  gameConfigScreenWidth <- getWord16le
  gameConfigScreenHeight <- getWord16le
  gameConfigVolume <- getWord8
  pure $ GameConfig{..}
```

We have solved the problem of the sleepy dev!  That aside, the big win here is that we can look at the parser in complete isolation - no flipping to the data declaration.  All we have to worry about is that we parse the fields in the correct order, which is the main problem we were solving anyways!  We don't have to worry about the fields in the data structure being laid out in the same order as the bytes in the file.
