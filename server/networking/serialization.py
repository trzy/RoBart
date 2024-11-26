#
# serialization.py
# Bart Trzynadlowski
#
#
# This file is part of RoBart.
#
# RoBart is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# RoBart is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with RoBart. If not, see <http://www.gnu.org/licenses/>.
#

#
# Serializes Pydantic BaseModel objects into messages (JSON with an "__id" field added set to the
# class name).
#
# For example:
#
#   HelloMessage(BaseModel):
#       message: str
#
# Serializes to:
#
#   { "__id": "HelloMessage", "message": "Message here." }
#

import json
from typing import Any, Dict, Type

from pydantic import BaseModel


def serialize(message: BaseModel) -> str:
    dictionary = message.model_dump()
    dictionary["__id"] = message.__class__.__name__
    return json.dumps(dictionary)

def deserialize(message_type: Type[BaseModel], dictionary: Dict[str, Any]) -> Any:
    return message_type.parse_obj(dictionary)