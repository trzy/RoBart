/*
 * time.hpp
 * RoBart
 * Bart Trzynadlowski, 2024
 *
 * Time point and duration data structures that are slightly more ergonomic than their STL
 * counterparts.
 *
 * Taken from: https://github.com/trzy/PixArt
 *
 * This file is part of RoBart.
 *
 * RoBart is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 *
 * RoBart is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with RoBart. If not, see <http://www.gnu.org/licenses/>.
 */

 #pragma once
#ifndef INCLUDED_TIME_HPP
#define INCLUDED_TIME_HPP

#include <Arduino.h>

namespace util
{
  namespace time
  {
    namespace detail
    {
      struct duration_base
      {
        int64_t count = 0;

        duration_base(int64_t in_count)
          : count(in_count)
        {
        }
      };
    } // detail

    static uint64_t now()
    {
      return micros();
    }

    template <typename Resolution>
    struct duration: public detail::duration_base
    {
      template <typename RHSResolution>
      duration operator+(const duration<RHSResolution> &rhs) const
      {
        // Perform operation at highest precision
        // NOTE: assumes lowest-precision operand is still convertible to microseconds w/out overflow
        int64_t lhs_ticks = count * Resolution::Ticks;
        int64_t rhs_ticks = rhs.count * RHSResolution::Ticks;
        int64_t sum = lhs_ticks + rhs_ticks;
        return duration(sum / Resolution::Ticks);
      }

      template <typename RHSResolution>
      duration operator-(const duration<RHSResolution> &rhs) const
      {
        int64_t lhs_ticks = count * Resolution::Ticks;
        int64_t rhs_ticks = rhs.count * RHSResolution::Ticks;
        int64_t difference = lhs_ticks - rhs_ticks;
        return duration(difference / Resolution::Ticks);
      }

      template <typename RHSResolution>
      duration operator+=(const duration<RHSResolution> &rhs)
      {
        *this = *this + rhs;
        return *this;
      }

      template <typename RHSResolution>
      duration operator-=(const duration<RHSResolution> &rhs)
      {
        *this = *this - rhs;
        return *this;
      }

      template <typename RHSResolution>
      bool operator>(const duration<RHSResolution> &rhs) const
      {
        int64_t lhs_ticks = count * Resolution::Ticks;
        int64_t rhs_ticks = rhs.count * RHSResolution::Ticks;
        return lhs_ticks > rhs_ticks;
      }

      template <typename RHSResolution>
      bool operator>=(const duration<RHSResolution> &rhs) const
      {
        int64_t lhs_ticks = count * Resolution::Ticks;
        int64_t rhs_ticks = rhs.count * RHSResolution::Ticks;
        return lhs_ticks >= rhs_ticks;
      }

      template <typename RHSResolution>
      bool operator<(const duration<RHSResolution> &rhs) const
      {
        int64_t lhs_ticks = count * Resolution::Ticks;
        int64_t rhs_ticks = rhs.count * RHSResolution::Ticks;
        return lhs_ticks < rhs_ticks;
      }

      template <typename RHSResolution>
      bool operator<=(const duration<RHSResolution> &rhs) const
      {
        int64_t lhs_ticks = count * Resolution::Ticks;
        int64_t rhs_ticks = rhs.count * RHSResolution::Ticks;
        return lhs_ticks <= rhs_ticks;
      }

      duration(const int64_t in_count)
        : detail::duration_base(in_count)
      {
      }

      template <typename InResolution>
      duration(const duration<InResolution> &delta)
        : detail::duration_base(delta.count * (double(InResolution::Ticks) / double(Resolution::Ticks)))
      {
      }
    };

    struct microsecond
    {
      struct resolution
      {
        static const constexpr int64_t Ticks = 1;
      };
    };

    struct millisecond
    {
      struct resolution
      {
        static const constexpr int64_t Ticks = 1000;
      };
    };

    struct second
    {
      struct resolution
      {
        static const constexpr int64_t Ticks = 1000000;
      };
    };
  } // time

  using microsecond = time::microsecond;
  using millisecond = time::millisecond;
  using second = time::second;

  inline time::duration<microsecond::resolution> microseconds(int64_t count)
  {
    return count;
  }

  inline time::duration<millisecond::resolution> milliseconds(int64_t count)
  {
    return count;
  }

  inline time::duration<second::resolution> seconds(int64_t count)
  {
    return count;
  }
} // util

#endif  // INCLUDED_TIME_HPP