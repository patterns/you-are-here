
struct Point {
    double x;
    double y;
};

#ifdef __cplusplus
extern "C" {
#endif

struct Point mercator(double lat, double lng);

#ifdef __cplusplus
}
#endif
