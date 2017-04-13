module RespondSignal exposing (..)

import GenGame
    exposing
        ( Direction
        , TrialResult(Continuing, ContinuingWithEvent, Complete)
        , Reason(GoSuccess, NoGoSuccess, IndicationTimeout, WrongIndication, IndicatedOnNoGo)
        , TrialFuns
        , checkTransition
        , updateReason
        , bounded
        )
import Html exposing (Html, img, text)
import Html.Attributes exposing (class, src)
import List.Extra
import Random exposing (Generator)
import Random.Extra
import Random.List
import Time exposing (Time)


type alias Trial =
    { imageUrl : String
    , kind : Kind
    , stage : Stage
    , reason : Maybe Reason
    }


type Stage
    = NotStarted
    | PicturePreAudio Time
    | PicturePostAudio Time
    | Feedback Time


type Kind
    = Go
    | NoGo


type alias Settings msg =
    { totalPictureTime : Time
    , delayMin : Time
    , delayMax : Time
    , blockTrialCount : Int
    , responseCount : Int
    , nonResponseCount : Int
    , fillerCount : Int
    , feedback : Time
    , audioDelay : Time
    , delaySuccessChange : Time
    , delayFailureChange : Time
    , minDelay : Time
    , maxDelay : Time
    , audioEvent : Cmd msg
    }


init : Settings msg -> List String -> List String -> List String -> Generator (List (List Trial))
init settings responseUrls nonResponseUrls fillerUrls =
    Random.Extra.andThen3
        (\sGo sNoGo sFill ->
            let
                go =
                    List.take settings.responseCount sGo

                noGo =
                    List.take settings.nonResponseCount sNoGo

                fill =
                    List.take settings.fillerCount sFill

                goFillLen =
                    (List.length fill + 1) // 2

                goFill =
                    List.take goFillLen fill

                noGoFill =
                    List.drop goFillLen fill

                allGo =
                    List.map (initTrial Go) (goFill ++ go ++ go)

                allNoGo =
                    List.map (initTrial NoGo) (noGoFill ++ noGo ++ noGo)
            in
                (allGo ++ allNoGo)
                    |> Random.List.shuffle
                    |> Random.map (List.Extra.greedyGroupsOf settings.blockTrialCount)
        )
        (Random.List.shuffle responseUrls)
        (Random.List.shuffle nonResponseUrls)
        (Random.List.shuffle fillerUrls)


initTrial : Kind -> String -> Trial
initTrial kind url =
    { imageUrl = url
    , kind = kind
    , stage = NotStarted
    , reason = Nothing
    }


trialFuns : TrialFuns (Settings msg) Trial msg
trialFuns =
    { getTrialImages = always []
    , updateTime = updateTime
    , updateIndication = updateIndication
    , updateDirectionIndication = GenGame.defaultUpdateWithIndication
    , updateIntIndication = GenGame.defaultUpdateWithIndication
    , view = view
    }


isGo : Kind -> Bool
isGo kind =
    case kind of
        Go ->
            True

        NoGo ->
            False


updateTime : Settings msg -> Time -> Trial -> ( TrialResult Trial msg, Settings msg )
updateTime settings currTime trial =
    ( updateTimeHelper settings currTime trial, settings )


updateTimeHelper : Settings msg -> Time -> Trial -> TrialResult Trial msg
updateTimeHelper settings currTime trial =
    let
        trans =
            checkTransition trial currTime
    in
        case trial.stage of
            NotStarted ->
                case trial.kind of
                    Go ->
                        Continuing ({ trial | stage = PicturePreAudio currTime })

                    NoGo ->
                        Continuing ({ trial | stage = PicturePostAudio currTime })

            PicturePreAudio timeSince ->
                trans
                    timeSince
                    settings.audioDelay
                    (ContinuingWithEvent
                        { trial | stage = PicturePostAudio currTime }
                        settings.audioEvent
                    )

            PicturePostAudio timeSince ->
                let
                    reason =
                        if isGo trial.kind then
                            IndicationTimeout
                        else
                            NoGoSuccess

                    delay =
                        case trial.kind of
                            Go ->
                                settings.audioDelay

                            NoGo ->
                                0
                in
                    trans
                        timeSince
                        (settings.totalPictureTime - delay)
                        (Continuing { trial | stage = Feedback currTime, reason = Just reason })

            Feedback timeSince ->
                trans timeSince
                    settings.feedback
                    (Complete trial.reason)


updateIndication : Settings msg -> Time -> Trial -> ( TrialResult Trial msg, Settings msg )
updateIndication settings currTime trial =
    case trial.stage of
        PicturePostAudio _ ->
            if isGo trial.kind then
                ( Continuing { trial | reason = updateReason (GoSuccess currTime) trial.reason }
                , { settings
                    | audioDelay =
                        bounded
                            settings.minDelay
                            settings.maxDelay
                            (settings.audioDelay + settings.delaySuccessChange)
                  }
                )
            else
                ( Continuing { trial | reason = updateReason (IndicatedOnNoGo currTime) trial.reason }
                , { settings
                    | audioDelay =
                        bounded
                            settings.minDelay
                            settings.maxDelay
                            (settings.audioDelay + settings.delayFailureChange)
                  }
                )

        _ ->
            ( Continuing trial, settings )


view : Trial -> Html msg
view trial =
    case trial.stage of
        NotStarted ->
            pictureView trial.imageUrl

        PicturePreAudio _ ->
            pictureView trial.imageUrl

        PicturePostAudio _ ->
            pictureView trial.imageUrl

        Feedback _ ->
            text "Implement feedback display."


pictureView : String -> Html msg
pictureView url =
    img [ src url ] []
