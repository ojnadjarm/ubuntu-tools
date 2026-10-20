// Tracy smoke: 3 s of frames with two nested zones.
#include <chrono>
#include <cmath>
#include <thread>
#include <tracy/Tracy.hpp>

static double work(int n) {
	ZoneScopedN("work");
	double s = 0;
	for (int i = 0; i < n; i++) s += std::sin(i);
	return s;
}

int main() {
	std::this_thread::sleep_for(std::chrono::milliseconds(500));
	auto end = std::chrono::steady_clock::now() + std::chrono::seconds(3);
	volatile double sink = 0;
	while (std::chrono::steady_clock::now() < end) {
		ZoneScopedN("frame");
		sink = sink + work(200000);
		std::this_thread::sleep_for(std::chrono::milliseconds(8));
		FrameMark;
	}
	return 0;
}
