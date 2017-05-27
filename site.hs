{-# LANGUAGE OverloadedStrings #-}

import Data.Monoid (mappend)
import Hakyll
import System.FilePath

main :: IO ()
main =
  hakyll $ do
    match "semantic/dist/themes/default/assets/fonts/*" $ do
      route $ customRoute $ (("themes" </> "default" </> "assets" </> "fonts") </>) . takeFileName . toFilePath
      compile copyFileCompiler
    match "semantic/dist/components/*.min.js" $ do
      route $ customRoute $ ("js" </>) . takeFileName . toFilePath
      compile copyFileCompiler
    match "semantic/dist/components/*.min.css" $ do
      route $ customRoute $ ("css" </>) . takeFileName . toFilePath
      compile copyFileCompiler
    match "js/*" $ do
      route idRoute
      compile copyFileCompiler
    match "css/*" $ do
      route idRoute
      compile compressCssCompiler
    match "images/*" $ do
      route idRoute
      compile copyFileCompiler
    match "posts/*" $ do
      route $ setExtension "html"
      compile $
        pandocCompiler >>= loadAndApplyTemplate "templates/post.html" postCtx >>=
        loadAndApplyTemplate "templates/default.html" postCtx >>=
        relativizeUrls
    create ["archive.html"] $ do
      route idRoute
      compile $ do
        posts <- recentFirst =<< loadAll "posts/*"
        let archiveCtx =
              listField "posts" postCtx (return posts) `mappend`
              constField "title" "Blog" `mappend`
              defaultContext
        makeItem "" >>= loadAndApplyTemplate "templates/archive.html" archiveCtx >>=
          loadAndApplyTemplate "templates/default.html" archiveCtx >>=
          relativizeUrls
    match (fromList ["about.html", "contact.html"]) $ do
      route idRoute
      compile $ do
        let aboutCtx = defaultContext
        getResourceBody >>= applyAsTemplate aboutCtx >>=
          loadAndApplyTemplate "templates/default.html" aboutCtx >>=
          relativizeUrls
    match "index.html" $ do
      route idRoute
      compile $ do
        posts <- recentFirst =<< loadAll "posts/*"
        let indexCtx =
              listField "posts" postCtx (return posts) `mappend`
              defaultContext
        getResourceBody >>= applyAsTemplate indexCtx >>=
          loadAndApplyTemplate "templates/default.html" indexCtx >>=
          relativizeUrls
    match "templates/*" $ compile templateCompiler

postCtx :: Context String
postCtx = dateField "date" "%B %e, %Y" `mappend` defaultContext
