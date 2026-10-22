#include <cassert>
#include <cstdio>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <future>
#include <thread>

/* This is extracted verbatim from the staged SweetFramebuffer.cpp. */
#include A5_SWAP_STATE_HEADER

struct Harness {
	std::mutex lock;
	std::condition_variable changed;
	A5SwapWaitState state{};
	void issue(uint32_t id) {
		std::lock_guard<std::mutex> guard(lock);
		state.issue(id);
		changed.notify_all();
	}
	void finish(uint32_t id, A5SwapStatus status) {
		std::lock_guard<std::mutex> guard(lock);
		state.finish(id, status);
		changed.notify_all();
	}
	A5SwapStatus wait(uint32_t id, std::chrono::milliseconds timeout, std::promise<void> *entered = nullptr) {
		std::unique_lock<std::mutex> guard(lock);
		if (entered) entered->set_value();
		if (timeout.count() == 0) {
			changed.wait(guard, [&] { return state.status(id) != kA5SwapPending; });
		} else {
			changed.wait_for(guard, timeout,
			    [&] { return state.status(id) != kA5SwapPending; });
		}
		return state.status(id);
	}
};

int main() {
	using namespace std::chrono_literals;
	Harness h;
	assert(h.state.status(0) == kA5SwapShown);
	h.issue(1);
	assert(h.wait(1, 1ms) == kA5SwapPending); // finite deadline
	A5SwapStatus woke = kA5SwapUnknown;
	std::promise<void> entered;
	std::thread waiter([&] { woke = h.wait(1, 0ms, &entered); }); // zero = no deadline
	entered.get_future().get();
	h.finish(1, kA5SwapShown); // waiter-before-complete
	waiter.join();
	assert(woke == kA5SwapShown);
	assert(h.wait(1, 1ms) == kA5SwapShown); // complete-before-wait
	h.issue(2);
	std::promise<void> enteredDrop;
	std::thread droppedWaiter([&] { woke = h.wait(2, 0ms, &enteredDrop); });
	enteredDrop.get_future().get();
	h.finish(2, kA5SwapDropped); // overwritten pending record
	droppedWaiter.join();
	assert(woke == kA5SwapDropped);
	h.finish(2, kA5SwapShown); // terminal drop cannot be overwritten
	assert(h.wait(2, 1ms) == kA5SwapDropped);
	h.issue(3);
	assert(a5_swap_completion(true, false) == kA5SwapShown); // alias/blank/all copied
	assert(a5_swap_completion(true, true) == kA5SwapFailed); // uncertain DMA
	assert(a5_swap_completion(false, false) == kA5SwapFailed); // missing layer
	h.finish(3, a5_swap_completion(true, true));
	assert(h.wait(3, 1ms) == kA5SwapFailed);
	for (uint32_t id = 4; id <= 67; ++id)
		h.issue(id);
	assert(h.state.status(3) == kA5SwapUnknown); // bounded history
	assert(h.state.status(67) == kA5SwapPending);
	puts("swap outcomes and host wait predicates PASS (not IOKit/device execution)");
}
