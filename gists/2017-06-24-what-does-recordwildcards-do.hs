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
