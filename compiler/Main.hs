module Main where

import Kitten

import System.Environment
import System.IO
import System.Exit

main :: IO ()
main = do
  args <- getArgs
  case length args of
    1 -> do
      let filename = head args
      file <- readFile filename
      putStrLn file
      case compile filename file of
        Left compileError   -> die compileError
        Right compileResult -> print compileResult
    _ ->
      die "Usage: kitten FILENAME\n"

die
  :: (Show a)
  => a
  -> IO ()
die msg = do
  hPutStr stderr $ show msg
  exitFailure
