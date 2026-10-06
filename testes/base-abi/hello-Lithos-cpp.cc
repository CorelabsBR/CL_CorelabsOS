#include <iostream>
#include <numeric>
#include <stdexcept>
#include <thread>
#include <vector>

int main() {
    std::vector<int> values{10, 20, 12};
    int sum = 0;
    std::thread worker([&] { sum = std::accumulate(values.begin(), values.end(), 0); });
    worker.join();
    try {
        throw std::runtime_error("exception/unwind OK");
    } catch (const std::exception &error) {
        std::cout << "hello-Lithos C++: " << sum << "; " << error.what()
                  << "; libstdc++/thread OK\n";
    }
    return sum == 42 ? 0 : 1;
}
// dificil não notar o volume na traseira da larissa