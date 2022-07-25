import 'dart:convert';
import 'dart:io';

import 'package:authing_sdk/client.dart';
import 'package:authing_sdk/oidc/auth_request.dart';
import 'package:authing_sdk/user.dart';
import 'package:authing_sdk/util.dart';

import '../authing.dart';
import '../result.dart';
import 'cookie_manager.dart';

class OIDCClient {
  /// Build authorize URL
  static Future<String> buildAuthorizeUrl(AuthRequest authRequest) async {
    return 'https://' +
        Util.getHost(Authing.config) +
        '/oidc/auth?_authing_lang=' +
        authRequest.authingLang +
        "&app_id=" +
        Authing.sAppId +
        "&client_id=" +
        Authing.sAppId +
        "&nonce=" +
        authRequest.nonce +
        "&redirect_uri=" +
        authRequest.redirectUrl +
        "&response_type=" +
        authRequest.responseType +
        "&scope=" +
        authRequest.scope +
        "&prompt=consent" +
        "&state=" +
        authRequest.state +
        "&code_challenge=" +
        authRequest.codeChallenge +
        "&code_challenge_method=" +
        'S256';
  }

  /// OIDC prepare
  static Future<AuthResult> prepareLogin() async {
    AuthRequest authData = AuthRequest();
    authData.createAuthRequest();
    if (Authing.config.redirectUris.isEmpty == false) {
      authData.redirectUrl = Authing.config.redirectUris.first;
    }

    var url = Uri.parse('https://' +
        Util.getHost(Authing.config) +
        '/oidc/auth?_authing_lang=' +
        authData.authingLang +
        "&app_id=" +
        Authing.sAppId +
        "&client_id=" +
        Authing.sAppId +
        "&nonce=" +
        authData.nonce +
        "&redirect_uri=" +
        authData.redirectUrl +
        "&response_type=" +
        authData.responseType +
        "&scope=" +
        authData.scope +
        "&prompt=consent" +
        "&state=" +
        authData.state +
        "&code_challenge=" +
        authData.codeChallenge +
        "&code_challenge_method=" +
        'S256');

    var client = HttpClient();
    HttpClientRequest request = await client.getUrl(url);
    request.followRedirects = false;

    HttpClientResponse response = await request.close();
    var res = await response.transform(utf8.decoder).join();

    Result result = Result();
    if (response.statusCode == 302) {
      CookieManager().addCookies(response);
      String? location = response.headers["location"]?.first;
      String uuid = Uri.parse(location ?? '').pathSegments.last;
      authData.uuid = uuid;

      result.code = 200;
      AuthResult authResult = AuthResult(result, authRequest: authData);
      return authResult;
    } else {
      result.code = response.statusCode;
      result.message = "OIDC prepare login failed. " + res;
      AuthResult authResult = AuthResult(result);
      return authResult;
    }
  }

  /// OIDC register a new user by email address and a password.
  static Future<AuthResult> registerByEmail(
      String email, String password) async {
    AuthResult authResult = await OIDCClient.prepareLogin();
    if (authResult.code == 200) {
      return AuthClient.registerByEmail(email, password,
          authData: authResult.authData);
    } else {
      return authResult;
    }
  }

  /// OIDC register a new user by username and a password.
  static Future<AuthResult> registerByUserName(
      String username, String password) async {
    AuthResult authResult = await OIDCClient.prepareLogin();
    if (authResult.code == 200) {
      return AuthClient.registerByUserName(username, password,
          authData: authResult.authData);
    } else {
      return authResult;
    }
  }

  /// OIDC register a new user by phone number and an SMS verification code.
  static Future<AuthResult> registerByPhoneCode(
      String phone, String code, String password) async {
    AuthResult authResult = await OIDCClient.prepareLogin();
    if (authResult.code == 200) {
      return AuthClient.registerByPhoneCode(phone, code, password,
          authData: authResult.authData);
    } else {
      return authResult;
    }
  }

  /// OIDC Login by account and password
  static Future<AuthResult> loginByAccount(
      String account, String password) async {
    AuthResult authResult = await OIDCClient.prepareLogin();
    if (authResult.code == 200) {
      return AuthClient.loginByAccount(account, password,
          authData: authResult.authData);
    } else {
      return authResult;
    }
  }

  ///OIDC Login by phone code #
  static Future<AuthResult> loginByPhoneCode(String phone, String code) async {
    AuthResult authResult = await OIDCClient.prepareLogin();
    if (authResult.code == 200) {
      return AuthClient.loginByPhoneCode(phone, code,
          authData: authResult.authData);
    } else {
      return authResult;
    }
  }

  ///Auth by code #
  static Future<AuthResult> authByCode(
      String code, AuthRequest authRequest) async {
    String url = "https://" + Util.getHost(Authing.config) + "/oidc/token";
    String body = "client_id=" +
        Authing.sAppId +
        "&grant_type=authorization_code" +
        "&code=" +
        code +
        "&scope=" +
        authRequest.scope +
        "&prompt=" +
        "consent" +
        "&code_verifier=" +
        authRequest.codeVerifier +
        "&redirect_uri=" +
        Uri.encodeComponent(authRequest.redirectUrl);

    Result result = await oauthRequest("post", url, body);

    AuthResult authResult = AuthResult(result);

    if (authResult.code == 200 || authResult.code == 201) {
      authResult.user = await AuthClient.createUser(result);
      return getUserInfoByAccessToken(
          authResult.user?.accessToken ?? "", result.data);
    } else {
      return authResult;
    }
  }

  ///Auth by Authing token
  static Future<AuthResult> authByToken(
      String token, AuthRequest authRequest) async {
    String url = "https://" + Util.getHost(Authing.config) + "/oidc/token";
    String body = "client_id=" +
        Authing.sAppId +
        "&grant_type=http://authing.cn/oidc/grant_type/authing_token" +
        "&token=" +
        token +
        "&scope=" +
        authRequest.scope +
        "&prompt=" +
        "consent" +
        "&code_verifier=" +
        authRequest.codeVerifier +
        "&redirect_uri=" +
        Uri.encodeComponent(authRequest.redirectUrl);

    Result result = await oauthRequest("post", url, body);

    AuthResult authResult = AuthResult(result);

    if (authResult.code == 200 || authResult.code == 201) {
      authResult.user = await AuthClient.createUser(result);
      return getUserInfoByAccessToken(
          authResult.user?.accessToken ?? "", result.data);
    } else {
      return authResult;
    }
  }

  static Future<Result> oauthRequest(
      String method, String uri, String body) async {
    var url = Uri.parse(uri);
    var client = HttpClient();
    HttpClientRequest request = await client.postUrl(url);
    request.headers.set('x-authing-request-from', 'sdk-flutter');
    request.headers.set('x-authing-lang', Util.getLangHeader());

    if (method.toLowerCase() == "post".toLowerCase()) {
      String type = (body.startsWith('{') || body.startsWith("[")) &&
              (body.endsWith("]") || body.endsWith("}"))
          ? "application/json; charset=utf-8"
          : "application/x-www-form-urlencoded; charset=utf-8";

      request.headers.set("content-type", type);
    }

    request.add(utf8.encode(body));

    HttpClientResponse response = await request.close();
    var res = await response.transform(utf8.decoder).join();
    Result result = Result();
    if (response.statusCode == 200 || response.statusCode == 201) {
      CookieManager().addCookies(response);
      result.code = 200;
      result.message = "success";
      result.data = jsonDecode(res);
      return result;
    } else {
      result.code = response.statusCode;
      result.message = "authRequest failed. " + res;
      return result;
    }
  }

  ///Token Change user information
  static Future<AuthResult> getUserInfoByAccessToken(String accessToken,
      [Map? data]) async {
    String url = "https://" + Util.getHost(Authing.config) + "/oidc/me";
    var client = HttpClient();
    HttpClientRequest request = await client.getUrl(Uri.parse(url));

    request.headers.set("Authorization", "Bearer " + accessToken);

    HttpClientResponse response = await request.close();
    var res = await response.transform(utf8.decoder).join();
    Result result = Result();
    if (response.statusCode == 200) {
      result.code = 200;
      result.message = "success";
      result.data = jsonDecode(res);
      AuthResult authResult = AuthResult(result);
      authResult.user = await AuthClient.createUser(result);
      authResult.user =
          await User.update(authResult.user ?? User(), data ?? {});
      return authResult;
    } else {
      result.code = response.statusCode;
      result.message = "getUserInfoByAccessToken failed. " + res;
      AuthResult authResult = AuthResult(result);
      return authResult;
    }
  }

  ///Refresh Access Token
  static Future<AuthResult> getNewAccessTokenByRefreshToken(
      String refreshToken) async {
    String url = "https://" + Util.getHost(Authing.config) + "/oidc/token";
    String body = "client_id=" +
        Authing.sAppId +
        "&grant_type=refresh_token" +
        "&refresh_token=" +
        refreshToken;

    Result result = await oauthRequest("post", url, body);

    AuthResult authResult = AuthResult(result);

    if (authResult.code == 200 || authResult.code == 201) {
      authResult.user = User.create(result.data);

      return authResult;
    } else {
      return authResult;
    }
  }
}
