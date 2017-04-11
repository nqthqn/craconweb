module Api
    exposing
        ( jwtDecoded
        , okyToky
        , isAdmin
        , fetchGame
        , fetchUser
        , fetchUsers
        , fetchGroup
        , fetchRole
        , createUserRecord
        , createAuthRecord
        , fetchAll
        )

import Entity
import Http
import Task exposing (Task)
import Jwt
import Time
import Model as M
import Json.Decode as JD


fetchAll : String -> M.JwtPayload -> String -> Cmd M.Msg
fetchAll httpsrv jwt token =
    case isAdmin jwt of
        True ->
            Cmd.batch <|
                (userData httpsrv token jwt.sub)
                    ++ (adminData httpsrv token)

        False ->
            Cmd.batch <| userData httpsrv token jwt.sub



-- user, admin staff data, common


adminData : String -> String -> List (Cmd M.Msg)
adminData httpsrv token =
    [ Task.attempt M.UsersResp (fetchUsers_ httpsrv token)
    , Task.attempt M.RoleResp (fetchRole httpsrv token "user")
    , Task.attempt M.GroupResp (fetchGroup httpsrv token "control_a")
    , Task.attempt M.GroupResp (fetchGroup httpsrv token "experimental_a")
    ]


userData : String -> String -> String -> List (Cmd M.Msg)
userData httpsrv token sub =
    [ Task.attempt M.GameResp (fetchGame httpsrv token "gonogo")
    , Task.attempt M.GameResp (fetchGame httpsrv token "dotprobe")
    , Task.attempt M.GameResp (fetchGame httpsrv token "stopsignal")
    , Task.attempt M.GameResp (fetchGame httpsrv token "respondsignal")
    , Task.attempt M.GameResp (fetchGame httpsrv token "visualsearch")
    , Task.attempt M.UserResp (fetchUser httpsrv token sub)
    , Task.attempt M.FillerResp (fetchFiller httpsrv token sub)
    , Task.attempt M.ValidResp (fetchValid httpsrv token sub)
    , Task.attempt M.InvalidResp (fetchInvalid httpsrv token sub)
    ]


defaultHeaders : String -> List Http.Header
defaultHeaders jwtencoded =
    let
        headers =
            [ Http.header "Accept" "application/json" ]

        authHeaders =
            case jwtencoded of
                "" ->
                    headers

                _ ->
                    (Http.header "Authorization" ("Bearer " ++ jwtencoded)) :: headers
    in
        authHeaders


createAuthRecord : String -> Entity.AuthRecord -> Task Http.Error Entity.Auth
createAuthRecord httpsrv authRecord =
    Http.request
        { method = "POST"
        , headers = []
        , url = httpsrv ++ "/auth"
        , body = (Entity.authRecordEncoder authRecord |> Http.jsonBody)
        , expect = Http.expectJson Entity.authDecoder
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.toTask



-- get Role id then fetch users


fetchUsers_ : String -> String -> Task Http.Error (List Entity.User)
fetchUsers_ httpsrv token =
    fetchRole httpsrv token "user"
        |> Task.andThen (fetchUsersInRole httpsrv token << .id)


fetchFiller : String -> String -> String -> Task M.ValuationsError (List Entity.Ugimage)
fetchFiller httpsrv token sub =
    fetchImages httpsrv token sub "40" "filler"


fetchValid : String -> String -> String -> Task M.ValuationsError (List Entity.Ugimage)
fetchValid httpsrv token sub =
    fetchImages httpsrv token sub "80" "valid"


fetchInvalid : String -> String -> String -> Task M.ValuationsError (List Entity.Ugimage)
fetchInvalid httpsrv token sub =
    fetchImages httpsrv token sub "80" "invalid"


fetchImages : String -> String -> String -> String -> String -> Task M.ValuationsError (List Entity.Ugimage)
fetchImages httpsrv token sub count kind =
    fetchUgimgsets httpsrv token sub
        |> Task.mapError M.ReqFail
        |> Task.andThen
            (\ugimgsets ->
                case ugimsetsToString ugimgsets of
                    Just id ->
                        fetchUgimages httpsrv token count kind id
                            |> Task.mapError M.ReqFail

                    Nothing ->
                        Task.fail M.MissingValuations
            )


ugimsetsToString : List Entity.Ugimgset -> Maybe String
ugimsetsToString ugimgset =
    ugimgset
        |> List.head
        |> Maybe.map .id


fetchUgimages : String -> String -> String -> String -> String -> Task Http.Error (List Entity.Ugimage)
fetchUgimages httpsrv token limit gimgtypeSlug ugimgsetId =
    getRequest token
        (httpsrv
            ++ "/ugimgset/"
            ++ ugimgsetId
            ++ "/ugimages?valDesc=true&limit="
            ++ limit
            ++ "&valEach=true&gimgtypeSlug="
            ++ gimgtypeSlug
        )
        M.ugimageDecoder


fetchUgimgsets : String -> String -> String -> Task Http.Error (List Entity.Ugimgset)
fetchUgimgsets httpsrv token sub =
    getRequest token
        (httpsrv
            ++ "/user/"
            ++ sub
            ++ "/ugimgsets?createdDesc=true&limit=1&createdEach=true"
        )
        M.ugimgsetsDecoder


fetchGame : String -> String -> String -> Task Http.Error Entity.Game
fetchGame httpsrv token slug =
    getRequest token (httpsrv ++ "/game/" ++ slug) Entity.gameDecoder


fetchUser : String -> String -> String -> Task Http.Error Entity.User
fetchUser httpsrv token sub =
    getRequest token (httpsrv ++ "/user/" ++ sub) Entity.userDecoder


fetchUsers : String -> String -> Task Http.Error (List Entity.User)
fetchUsers httpsrv token =
    getRequest token (httpsrv ++ "/users?createdEach=true") (JD.field "users" (JD.list Entity.userDecoder))


fetchUsersInRole : String -> String -> String -> Task Http.Error (List Entity.User)
fetchUsersInRole httpsrv token roleId =
    getRequest token (httpsrv ++ "/users?createdEach=true&roleId=" ++ roleId) (JD.field "users" (JD.list Entity.userDecoder))


fetchGroup : String -> String -> String -> Task Http.Error Entity.Group
fetchGroup httpsrv token slug =
    getRequest token (httpsrv ++ "/group/" ++ slug) Entity.groupDecoder


fetchRole : String -> String -> String -> Task Http.Error Entity.Role
fetchRole httpsrv token slug =
    getRequest token (httpsrv ++ "/role/" ++ slug) Entity.roleDecoder


createUserRecord :
    String
    -> String
    -> Entity.UserRecord
    -> Task Http.Error Entity.User
createUserRecord httpsrv token user =
    Http.request
        { method = "POST"
        , headers = defaultHeaders token
        , url = httpsrv ++ "/user"
        , body = Http.jsonBody <| Entity.userRecordEncoder user
        , expect = Http.expectJson Entity.userDecoder
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.toTask


getRequest : String -> String -> JD.Decoder a -> Task Http.Error a
getRequest token endpoint jsonDecoder =
    Http.request
        { method = "GET"
        , headers = defaultHeaders token
        , url = endpoint
        , body = Http.emptyBody
        , expect = Http.expectJson jsonDecoder
        , timeout = Nothing
        , withCredentials = False
        }
        |> Http.toTask


isAdmin : M.JwtPayload -> Bool
isAdmin jwt =
    List.map .name jwt.roles |> List.member "admin"


okyToky : Time.Time -> String -> Result String M.JwtPayload
okyToky now token =
    case Jwt.decodeToken M.jwtDecoder token of
        Ok decoded ->
            case Jwt.isExpired now token of
                Ok True ->
                    Err "Expired"

                Ok False ->
                    Ok decoded

                Err jwtErr ->
                    Err "Decoding Problem"

        _ ->
            Err "Decoding problem"



-- to humanize or not to?
--type JwtError
--    = HttpError Http.Error
--    | Unauthorized
--    | TokenExpired
--    | TokenNotExpired
--    | TokenProcessingError String
--    | TokenDecodeError String


jwtDecoded : String -> Result Jwt.JwtError M.JwtPayload
jwtDecoded token =
    Jwt.decodeToken M.jwtDecoder token
