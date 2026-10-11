from django.urls import include, path

urlpatterns = [
    path("api/v1/", include("apps.core.urls")),
    path("api/v1/auth/", include("apps.accounts.urls")),
    path("api/v1/sync/", include("apps.sync.urls")),
]

handler404 = "apps.core.views.not_found"
handler500 = "apps.core.views.server_error"
