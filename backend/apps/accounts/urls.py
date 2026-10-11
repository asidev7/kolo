from django.urls import path

from . import views

urlpatterns = [
    path("register", views.RegisterView.as_view(), name="auth-register"),
    path("login", views.LoginView.as_view(), name="auth-login"),
    path("refresh", views.RefreshView.as_view(), name="auth-refresh"),
    path("logout", views.LogoutView.as_view(), name="auth-logout"),
    path("me", views.MeView.as_view(), name="auth-me"),
    path("password/change", views.ChangePasswordView.as_view(), name="auth-password-change"),
    path("password/forgot", views.ForgotPasswordView.as_view(), name="auth-password-forgot"),
    path("password/reset", views.ResetPasswordView.as_view(), name="auth-password-reset"),
]
