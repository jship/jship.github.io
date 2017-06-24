#!/usr/bin/env stack
-- stack --resolver lts-8.20 --install-ghc exec ghci --package bytestring --package cereal

{-# LANGUAGE RecordWildCards #-}

import Data.ByteString (ByteString)
import Data.Serialize.Get (Get, getWord8, getWord16le, runGet)
import Data.Word (Word8, Word16)

data GameConfig = GameConfig
  { gameConfigScreenWidth  :: Word16
  , gameConfigScreenHeight :: Word16
  , gameConfigVolume       :: Word8
  } deriving (Show)

decodeGameConfig :: Get GameConfig -> ByteString -> Either String GameConfig
decodeGameConfig = runGet

applicativeGetter :: Get GameConfig
applicativeGetter = GameConfig <$> getWord16le <*> getWord16le <*> getWord8

monadicGetter :: Get GameConfig
monadicGetter = do
  screenWidth <- getWord16le
  screenHeight <- getWord16le
  volume <- getWord8
  pure $ GameConfig screenWidth screenHeight volume

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

monadicGetterWithRecordWildCards :: Get GameConfig
monadicGetterWithRecordWildCards = do
  gameConfigScreenWidth <- getWord16le
  gameConfigScreenHeight <- getWord16le
  gameConfigVolume <- getWord8
  pure $ GameConfig{..}
