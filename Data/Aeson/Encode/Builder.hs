{-# LANGUAGE BangPatterns, OverloadedStrings #-}

-- |
-- Module:      Data.Aeson.Encode.Builder
-- Copyright:   (c) 2011 MailRank, Inc.
--              (c) 2013 Simon Meier <iridcode@gmail.com>
-- License:     Apache
-- Maintainer:  Bryan O'Sullivan <bos@serpentine.com>
-- Stability:   experimental
-- Portability: portable
--
-- Efficiently serialize a JSON value using the UTF-8 encoding.

module Data.Aeson.Encode.Builder
    (
      encodeToBuilder
    , null_
    , bool
    , array
    , emptyArray_
    , emptyObject_
    , object
    , text
    , string
    , unquoted
    , number
    , day
    , localTime
    , utcTime
    , zonedTime
    , ascii2
    , ascii4
    , ascii5
    ) where

import Data.Aeson.Functions (fromPico)
import Data.Aeson.Types.Internal (Encoding(..), Value(..))
import Data.ByteString.Builder as B
import Data.ByteString.Builder.Prim as BP
import Data.ByteString.Builder.Scientific (scientificBuilder)
import Data.Char (chr, ord)
import Data.Int (Int64)
import Data.Monoid ((<>))
import Data.Scientific (Scientific, base10Exponent, coefficient)
import Data.Time (DiffTime, UTCTime(..))
import Data.Time.Calendar (Day(..), toGregorian)
import Data.Time.LocalTime
import Data.Word (Word8)
import Unsafe.Coerce (unsafeCoerce)
import qualified Data.HashMap.Strict as HMS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V

-- | Encode a JSON value to a "Data.ByteString" 'B.Builder'.
--
-- Use this function if you are encoding over the wire, or need to
-- prepend or append further bytes to the encoded JSON value.
encodeToBuilder :: Value -> Builder
encodeToBuilder Null       = null_
encodeToBuilder (Bool b)   = bool b
encodeToBuilder (Number n) = number n
encodeToBuilder (String s) = text s
encodeToBuilder (Array v)  = array v
encodeToBuilder (Object m) = object m

-- | Encode a JSON null.
null_ :: Builder
null_ = BP.primBounded (ascii4 ('n',('u',('l','l')))) ()

-- | Encode a JSON boolean.
bool :: Bool -> Builder
bool = BP.primBounded (BP.condB id (ascii4 ('t',('r',('u','e'))))
                                   (ascii5 ('f',('a',('l',('s','e'))))))

-- | Encode a JSON array.
array :: V.Vector Value -> Builder
array v
  | V.null v  = emptyArray__
  | otherwise = B.char8 '[' <>
                encodeToBuilder (V.unsafeHead v) <>
                V.foldr withComma (B.char8 ']') (V.unsafeTail v)
  where
    withComma a z = B.char8 ',' <> encodeToBuilder a <> z

-- Encode a JSON object.
object :: HMS.HashMap T.Text Value -> Builder
object m = case HMS.toList m of
    (x:xs) -> B.char8 '{' <> one x <> foldr withComma (B.char8 '}') xs
    _      -> emptyObject__
  where
    withComma a z = B.char8 ',' <> one a <> z
    one (k,v)     = text k <> B.char8 ':' <> encodeToBuilder v

-- | Encode a JSON string.
text :: T.Text -> Builder
text t = B.char8 '"' <> unquoted t <> B.char8 '"'

-- | Encode a JSON string, without enclosing quotes.
unquoted :: T.Text -> Builder
unquoted t = TE.encodeUtf8BuilderEscaped escapeAscii t

-- | Encode a JSON string.
string :: String -> Builder
string t = B.char8 '"' <> BP.primMapListBounded go t <> B.char8 '"'
  where go = BP.condB (> '\x7f') BP.charUtf8 (c2w >$< escapeAscii)

escapeAscii :: BP.BoundedPrim Word8
escapeAscii =
    BP.condB (== c2w '\\'  ) (ascii2 ('\\','\\')) $
    BP.condB (== c2w '\"'  ) (ascii2 ('\\','"' )) $
    BP.condB (>= c2w '\x20') (BP.liftFixedToBounded BP.word8) $
    BP.condB (== c2w '\n'  ) (ascii2 ('\\','n' )) $
    BP.condB (== c2w '\r'  ) (ascii2 ('\\','r' )) $
    BP.condB (== c2w '\t'  ) (ascii2 ('\\','t' )) $
    (BP.liftFixedToBounded hexEscape) -- fallback for chars < 0x20
  where
    hexEscape :: BP.FixedPrim Word8
    hexEscape = (\c -> ('\\', ('u', fromIntegral c))) BP.>$<
        BP.char8 >*< BP.char8 >*< BP.word16HexFixed
{-# INLINE escapeAscii #-}

c2w :: Char -> Word8
c2w c = fromIntegral (ord c)

-- | Encode a JSON number.
number :: Scientific -> Builder
number s
    | e < 0     = scientificBuilder s
    | otherwise = B.integerDec (coefficient s * 10 ^ e)
  where
    e = base10Exponent s

emptyArray_ :: Encoding
emptyArray_ = Encoding emptyArray__

emptyArray__ :: Builder
emptyArray__ = BP.primBounded (ascii2 ('[',']')) ()

emptyObject_ :: Encoding
emptyObject_ = Encoding emptyObject__

emptyObject__ :: Builder
emptyObject__ = BP.primBounded (ascii2 ('{','}')) ()

ascii2 :: (Char, Char) -> BP.BoundedPrim a
ascii2 cs = BP.liftFixedToBounded $ (const cs) BP.>$< BP.char7 >*< BP.char7
{-# INLINE ascii2 #-}

ascii4 :: (Char, (Char, (Char, Char))) -> BP.BoundedPrim a
ascii4 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7
{-# INLINE ascii4 #-}

ascii5 :: (Char, (Char, (Char, (Char, Char)))) -> BP.BoundedPrim a
ascii5 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7
{-# INLINE ascii5 #-}

ascii6 :: (Char, (Char, (Char, (Char, (Char, Char))))) -> BP.BoundedPrim a
ascii6 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7
{-# INLINE ascii6 #-}

ascii8 :: (Char, (Char, (Char, (Char, (Char, (Char, (Char, Char)))))))
       -> BP.BoundedPrim a
ascii8 cs = BP.liftFixedToBounded $ (const cs) >$<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7 >*<
    BP.char7 >*< BP.char7 >*< BP.char7 >*< BP.char7
{-# INLINE ascii8 #-}

day :: Day -> Builder
day dd = B.integerDec y <>
         BP.primBounded (ascii6 ('-',(mh,(ml,('-',(dh,dl)))))) ()
  where (y,m,d)     = toGregorian dd
        !(T mh ml)  = twoDigits m
        !(T dh dl)  = twoDigits d
{-# INLINE day #-}

timeOfDay :: TimeOfDay64 -> Builder
timeOfDay (TOD h m s)
  | micro100 < 5 = hhmmss -- omit trailing milliseconds if zero
  | otherwise    = hhmmss <> BP.primBounded (ascii4 ('.',(a,(b,c)))) ()
  where
    hhmmss  = BP.primBounded (ascii8 (hh,(hl,(':',(mh,(ml,(':',(sh,sl)))))))) ()
    !(T hh hl)  = twoDigits h
    !(T mh ml)  = twoDigits m
    !(T sh sl)  = twoDigits (fromIntegral real)
    (real,frac) = s `quotRem` 1000000000000
    -- Units of 100 microseconds (tenths of a millisecond), which we
    -- round up so that milliseconds >= 0.5 render correctly.
    micro100
      | d `rem` 10 < 5 = d
      | otherwise      = d + 10
      where d          = fromIntegral (frac `quot` 100000000)
    !(T a b)   = twoDigits ab
    (ab,cc)    = micro100 `quotRem` 100
    !c         = digit (cc `quot` 10)
{-# INLINE timeOfDay #-}

timeZone :: TimeZone -> Builder
timeZone (TimeZone off _ _)
  | off == 0  = B.char7 'Z'
  | otherwise = BP.primBounded (ascii5 (s,(hh,(hl,(mh,ml))))) ()
  where !s         = if off < 0 then '-' else '+'
        !(T hh hl) = twoDigits h
        !(T mh ml) = twoDigits m
        (h,m)      = abs off `quotRem` 60
{-# INLINE timeZone #-}

dayTime :: Day -> TimeOfDay64 -> Builder
dayTime d t = day d <> B.char7 'T' <> timeOfDay t
{-# INLINE dayTime #-}

utcTime :: UTCTime -> B.Builder
utcTime (UTCTime d s) = dayTime d (diffTimeOfDay64 s) <> B.char7 'Z'
{-# INLINE utcTime #-}

data TimeOfDay64 = TOD {-# UNPACK #-} !Int
                       {-# UNPACK #-} !Int
                       {-# UNPACK #-} !Int64

diffTimeOfDay64 :: DiffTime -> TimeOfDay64
diffTimeOfDay64 t = TOD (fromIntegral h) (fromIntegral m) s
  where (h,mp) = fromIntegral pico `quotRem` 3600000000000000
        (m,s)  = mp `quotRem` 60000000000000
        pico   = unsafeCoerce t :: Integer

toTimeOfDay64 :: TimeOfDay -> TimeOfDay64
toTimeOfDay64 (TimeOfDay h m s) = TOD h m (fromIntegral (fromPico s))

localTime :: LocalTime -> Builder
localTime (LocalTime d t) = dayTime d (toTimeOfDay64 t)
{-# INLINE localTime #-}

zonedTime :: ZonedTime -> Builder
zonedTime (ZonedTime t z) = localTime t <> timeZone z
{-# INLINE zonedTime #-}

data T = T {-# UNPACK #-} !Char {-# UNPACK #-} !Char

twoDigits :: Int -> T
twoDigits a     = T (digit hi) (digit lo)
  where (hi,lo) = a `quotRem` 10

digit :: Int -> Char
digit x = chr (x + 48)
