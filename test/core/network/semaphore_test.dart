import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediamix/core/network/network_engine.dart';

void main() {
  group('Semaphore', () {
    test('初始可用许可数等于 max', () async {
      final sem = Semaphore(3);
      await sem.acquire();
      await sem.acquire();
      // 释放一个
      sem.release();
      // 可以再次获取
      await sem.acquire();
      // 此时已获取 2 个，还能再获取 1 个
      await sem.acquire();
      // 第 4 个 acquire 会阻塞
      final future = sem.acquire();
      // 释放一个后 future 完成
      sem.release();
      await future.timeout(const Duration(seconds: 1));
    });

    test('acquire 在无许可时等待', () async {
      final sem = Semaphore(1);
      await sem.acquire(); // 占用唯一许可

      var acquired = false;
      final future = sem.acquire().then((_) => acquired = true);

      // 给一点时间确认未完成
      await Future.delayed(const Duration(milliseconds: 50));
      expect(acquired, isFalse);

      sem.release();
      await future.timeout(const Duration(seconds: 1));
      expect(acquired, isTrue);
    });

    test('多个等待者按 FIFO 顺序获取', () async {
      final sem = Semaphore(1);
      await sem.acquire();

      final order = <int>[];
      final f1 = sem.acquire().then((_) => order.add(1));
      final f2 = sem.acquire().then((_) => order.add(2));
      final f3 = sem.acquire().then((_) => order.add(3));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(order, isEmpty);

      // 逐个释放
      sem.release();
      await f1.timeout(const Duration(seconds: 1));
      expect(order, equals([1]));

      sem.release();
      await f2.timeout(const Duration(seconds: 1));
      expect(order, equals([1, 2]));

      sem.release();
      await f3.timeout(const Duration(seconds: 1));
      expect(order, equals([1, 2, 3]));
    });

    test('释放超过初始数时增加可用许可', () async {
      final sem = Semaphore(1);
      sem.release(); // 许可 +1
      sem.release(); // 许可 +1

      // 可以连续获取3次
      await sem.acquire();
      await sem.acquire();
      await sem.acquire();

      // 第4次会阻塞
      var blocked = true;
      final future = sem.acquire().then((_) => blocked = false);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(blocked, isTrue);

      sem.release();
      await future.timeout(const Duration(seconds: 1));
      expect(blocked, isFalse);
    });
  });
}
