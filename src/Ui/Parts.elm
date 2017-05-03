module Ui.Parts exposing (notification, linkAttrs)

import Html exposing (..)
import Html.Attributes exposing (..)
import Model exposing (Msg(..))
import Html.Events exposing (onClick)
import Routing as R


notification : Maybe String -> String -> Html Msg
notification notifText mods =
    case notifText of
        Just nTxt ->
            div
                [ class <| "notification " ++ mods ]
                [ button [ class "delete", onClick ResetNotifications ] []
                , text nTxt
                ]

        Nothing ->
            div [] []


linkAttrs : String -> List (Attribute Msg)
linkAttrs path =
    [ href <| path, R.onLinkClick <| UpdateLocation path ]