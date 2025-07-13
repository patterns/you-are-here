
#include <s2/s2projections.h>
#include "bindings.h"

extern "C" Point mercator(double lat, double lng) {
    S2LatLng obj = S2LatLng::FromDegrees(lat, lng);
    S2::MercatorProjection mp = S2::MercatorProjection(0.5);
    R2Point projected = mp.FromLatLng(obj);

    Point p;
    p.x = projected.x();
    p.y = projected.y();
    return p;
}

