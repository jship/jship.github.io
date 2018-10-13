---
title: "Subvert Your Type Checker Today!"
author: Jason Shipman
tags: Haskell, Type Checker, Joke
---

### Motivation

Gabe Dijkstra's Haskell eXchange 2018
[talk](https://skillsmatter.com/skillscasts/12388-write-your-own-ghc-type-checker-plugins)
showed how we can write extensions to GHC's type checking via
plugins. The sky is the limit!

Do you wish you could do IO from
any monad transformer stack, including those stacks that do not have
`IO` at the base?  Do you think
[`RIO`](https://www.stackage.org/haddock/lts-12.12/rio-0.1.5.0/RIO.html#t:RIO)
is an interesting concept, but would rather just do `IO` from your
regular ol' `Reader` computations?  Prefer writing pure code in the
`Identity` monad for the sake of `do`-notation but still want to do some `IO`
in there?  Are you frustrated when you have to propagate `MonadIO` constraints
throughout a ladder of function calls?

Then this post is for you!

### Extending the Type Checker

Gabe Dijkstra's
[slides](https://github.com/gdijkstra/gdijkstra.github.io/blob/8582c5103208af93fab07077f200331580a9ca33/ghc-type-checker-plugins-haskell-exchange-2018.pdf)
from his talk break down how to build a type checker plugin. We won't
rehash everything Gabe explains in this blog post.  Instead, we'll get on
with writing a plugin right away.

Our module will export the required `plugin` binding. We name it `TcYolo` to
indicate to our users that it is a reliable type checker plugin and very
suitable for production use cases.

```haskell
module TcYolo
  ( plugin
  ) where
```

Ye olde wall o' imports - note that we'll need the
[`ghc`](https://www.stackage.org/lts-10.8/package/ghc-8.2.2) library for some
of these:

```haskell
import Class (className)
import Control.Monad (guard)
import Data.Maybe (mapMaybe)
import OccName (HasOccName(occName), mkClsOcc)
import Plugins (Plugin, defaultPlugin, tcPlugin)
import TcEvidence (EvTerm)
import TcRnTypes
  ( TcPlugin(TcPlugin, tcPluginInit, tcPluginSolve, tcPluginStop),
  , TcPluginResult(TcPluginOk), Ct, ctEvPred, ctEvTerm, ctEvidence
  )
import Type (PredTree(ClassPred), classifyPredType)
```

The exported type checker plugin:

```haskell
plugin :: Plugin
plugin = defaultPlugin
  { tcPlugin = const . pure $ TcPlugin
    { tcPluginInit = pure ()
    , tcPluginStop = const (pure ())
    , tcPluginSolve = \() _givenCts _derivedCts wantedCts ->
        pure . TcPluginOk (mapMaybe solveMonadIOCt wantedCts) $ []
    }
  }
```

And finally the constraint solver for what our plugin cares about -
adding the `MonadIO` constraint anywhere our users' code wants it!

```haskell
solveMonadIOCt :: Ct -> Maybe (EvTerm, Ct)
solveMonadIOCt ct = do
  ClassPred cls _types <- pure . classifyPredType . ctEvPred . ctEvidence $ ct
  guard (mkClsOcc "MonadIO" == occName (className cls))
  -- The first part of this pair is probably wrong? ¯\_(ツ)_/¯
  pure (ctEvTerm . ctEvidence $ ct, ct)
```

### Using the Plugin

We can use the plugin via the `-fplugin` GHC option:

```haskell
{-# OPTIONS_GHC -fplugin=TcYolo #-}

module TcYoloExample
  ( whereIsYourGodNow
  , noneShallPass
  , becauseWhyNot
  ) where

import Control.Monad.IO.Class (MonadIO(liftIO))
import Control.Monad.Trans.Except (Except)
import Control.Monad.Trans.Reader (Reader)
import Control.Monad.Trans.State (StateT, get)
import Data.Functor.Identity (Identity)
import System.IO.Error (userError)
import System.Random (Random(randomIO))

whereIsYourGodNow :: Reader () Int
whereIsYourGodNow = liftIO randomIO

noneShallPass :: Identity ()
noneShallPass = liftIO . ioError . userError $ "blah"

becauseWhyNot :: StateT Int (Except String) Int
becauseWhyNot = do
  fileLength <- fmap length (liftIO . readFile $ "some-file.txt")
  extraLength <- get
  pure $ fileLength + extraLength

-- Note that the above code typechecks, but termination is a different story! 😛
```

The plugin and example code are available in a repo
[here](https://github.com/jship/tc-yolo).
