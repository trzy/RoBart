using System;
using UnityEngine;

namespace Net
{
  [AttributeUsage(AttributeTargets.Method)]
  public class Handler: Attribute
  {
    public bool Unknown
    {
      get;
      private set;
    }

    public string MessageType
    {
      get;
      private set;
    }

    public bool Valid
    {
      get;
      private set;
    }

    public Handler(Type message)
    {
      Unknown = false;
      MessageType = message.Name;
      
      bool isStruct = message.IsValueType && !message.IsPrimitive && !message.IsArray && !message.IsEnum;
      if (!isStruct)
      {
        Debug.LogErrorFormat("Handler: Handler will not be invoked because {0} is not a struct", MessageType);
        Valid = false;
      }
      else
      {
        Valid = true;
      }
    }

    public Handler()
    {
      Unknown = true;
      MessageType = null;
      Valid = true;
    }
  }
}