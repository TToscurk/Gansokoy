"""Local MCP client for this Blender authoring work; never bypass the addon."""
import asyncio
import json
import sys
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

async def main():
    prompt = sys.argv[2] if len(sys.argv) > 2 else '請繼續精緻化'
    async with stdio_client(StdioServerParameters(command='uvx', args=['blender-mcp'])) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            if sys.argv[1] == '--inspect':
                for tool in (await session.list_tools()).tools:
                    if tool.name in ('execute_blender_code', 'get_viewport_screenshot', 'get_addon_status'):
                        print(tool.model_dump_json())
                result = await session.call_tool('get_addon_status', {'user_prompt': prompt})
            else:
                code = Path(sys.argv[1]).read_text(encoding='utf-8')
                result = await session.call_tool('execute_blender_code', {'code': code, 'user_prompt': prompt})
            print(result.model_dump_json())
            Path(__file__).with_name('last_mcp_result.json').write_text(result.model_dump_json(), encoding='utf-8')
            texts = [getattr(item, 'text', '') for item in result.content]
            if getattr(result, 'is_error', False) or any(
                text.startswith(('Error executing code:', 'Error executing tool')) for text in texts
            ):
                raise RuntimeError('Blender MCP returned an error; see last_mcp_result.json')

if __name__ == '__main__':
    asyncio.run(main())
