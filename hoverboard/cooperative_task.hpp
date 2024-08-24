/*
 * cooperative_task.hpp
 * RoBart
 * Bart Trzynadlowski, 2024
 *
 * Cooperative multitasking. Simply create a task and call tick() periodically.
 *
 * Taken from: https://github.com/trzy/PixArt
 */

#pragma once
#ifndef INCLUDED_COOPERATIVE_TASK_HPP
#define INCLUDED_COOPERATIVE_TASK_HPP

#pragma push_macro("min")
#pragma push_macro("max")
#undef min
#undef max

#include "time.hpp"
#include <functional>
#include <chrono>
#include <cstdint>

namespace util
{
  template <typename TimeResolution>
  class cooperative_task
  {
  public:
    void tick(int64_t now_micros)
    {
      if (!m_task_cb)
      {
        // No callback indicates default-constructed task, which would loop indefinitely
        return;
      }

      util::time::duration<util::microsecond::resolution> delta(now_micros - m_last_time);
      m_delta += delta;
      auto delta_since_last_tick = m_delta;
      m_last_time = now_micros;

      while (m_delta >= m_period)
      {
        if (m_task_cb)  // redundant check because Arduino doesn't implement std::__throw_bad_function_call()
        {
          m_task_cb(delta_since_last_tick, m_count);
        }
        m_delta -= m_period;
        m_count += 1;
      }
    }
  
    void tick()
    {
      tick(micros());
    }
  
    cooperative_task(util::time::duration<TimeResolution> period, const std::function<void(util::time::duration<util::microsecond::resolution>, size_t)> task)
      : m_task_cb(task),
        m_period(period),
        m_last_time(micros())
    {
    }
  
    cooperative_task()
      : m_last_time(micros())
    {
    }
  
  private:
    std::function<void(util::time::duration<util::microsecond::resolution>, size_t)> m_task_cb;
    util::time::duration<util::microsecond::resolution> m_period = 0;
    util::time::duration<util::microsecond::resolution> m_delta = 0;
    int64_t m_last_time;
    size_t m_count = 0;
  };
} // util

#pragma pop_macro("max")
#pragma pop_macro("min")

#endif  // INCLUDED_COOPERATIVE_TASK_HPP