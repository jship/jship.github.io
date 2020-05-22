{-# LANGUAGE OverloadedStrings #-}

import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Hakyll
import System.FilePath

main :: IO ()
main = do
  setLocaleEncoding utf8
  hakyll $ do
    match "semantic/dist/themes/default/assets/fonts/*" $ do
      route $
        customRoute $
        (("themes" </> "default" </> "assets" </> "fonts") </>) .
        takeFileName . toFilePath
      compile copyFileCompiler
    match "semantic/dist/*.min.js" $ do
      route $ customRoute $ ("js" </>) . takeFileName . toFilePath
      compile copyFileCompiler
    match "semantic/dist/components/*.min.js" $ do
      route $ customRoute $ ("js" </>) . takeFileName . toFilePath
      compile copyFileCompiler
    match "semantic/dist/*.min.css" $ do
      route $ customRoute $ ("css" </>) . takeFileName . toFilePath
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
    match "html/*" $ do
      route idRoute
      compile copyFileCompiler
    tags <- buildTags "posts/*" (fromCapture "tags/*.html")
    tagsRules tags $ \tag pattern -> do
      let title = "Posts tagged with \"" ++ tag ++ "\""
      route idRoute
      compile $ do
        posts <- recentFirst =<< loadAll pattern
        let ctx =
              constField "title" title `mappend`
              listField "posts" (postCtxWithTags tags) (return posts) `mappend`
              defaultContext
        makeItem "" >>= loadAndApplyTemplate "templates/tag.html" ctx >>=
          loadAndApplyTemplate "templates/default.html" ctx >>=
          relativizeUrls
    match "posts/*" $ do
      route $ setExtension "html"
      compile $
        pandocCompiler >>=
        loadAndApplyTemplate "templates/post.html" (postCtxWithTags tags) >>=
        saveSnapshot "content" >>=
        loadAndApplyTemplate "templates/default.html" (postCtxWithTags tags) >>=
        relativizeUrls
    create ["atom.xml"] $ do
      route idRoute
      compile $ do
        let feedCtx = postCtx `mappend` bodyField "description"
        posts <-
          fmap (take 10) . recentFirst =<< loadAllSnapshots "posts/*" "content"
        renderAtom feedConfig feedCtx posts
    create ["rss.xml"] $ do
      route idRoute
      compile $ do
        let feedCtx = postCtx `mappend` bodyField "description"
        posts <-
          fmap (take 10) . recentFirst =<< loadAllSnapshots "posts/*" "content"
        renderRss feedConfig feedCtx posts
    create ["archive.html"] $ do
      route idRoute
      compile $ do
        posts <- recentFirst =<< loadAll "posts/*"
        let archiveCtx =
              listField "posts" (postCtxWithTags tags) (return posts) `mappend`
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
        posts <- fmap (take 3) . recentFirst =<< loadAll "posts/*"
        let indexCtx =
              listField "posts" (postCtxWithTags tags) (return posts) `mappend`
              defaultContext
        getResourceBody >>= applyAsTemplate indexCtx >>=
          loadAndApplyTemplate "templates/default.html" indexCtx >>=
          relativizeUrls
    match "resume.md" $ do
      route $ setExtension "html"
      compile $
        pandocCompiler >>=
        loadAndApplyTemplate "templates/resume.html" defaultContext >>=
        loadAndApplyTemplate "templates/default.html" defaultContext >>=
        relativizeUrls
    match "templates/*" $ compile templateCompiler

postCtx :: Context String
postCtx = dateField "date" "%B %e, %Y" `mappend` defaultContext

postCtxWithTags :: Tags -> Context String
postCtxWithTags tags = tagsField "tags" tags `mappend` postCtx

feedConfig :: FeedConfiguration
feedConfig =
  FeedConfiguration
  { feedTitle = "jship's Personal Blog"
  , feedDescription = "This feed provides the latest blog posts from jship"
  , feedAuthorName = "Jason Shipman"
  , feedAuthorEmail = "jasonpshipman@gmail.com"
  , feedRoot = "https://jship.github.io"
  }
